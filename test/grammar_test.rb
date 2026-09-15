# frozen_string_literal: true

require "tempfile"
require "test_helper"

class GrammarTest < Minitest::Test
  FIXTURES = File.join(__dir__, "fixtures/grammar")

  def names(lexer, source)
    lexer.lex(source).map { |token, text| [token.qualname, text] }
  end

  def with_grammar(source, suffix = ".json")
    Tempfile.create(["grammar", suffix]) do |file|
      file.binmode
      file.write(source)
      file.flush
      yield file.path
    end
  end

  def test_json_grammar_supports_repository_captures_and_dynamic_begin_end
    lexer = Antares::Grammar.load_tmlanguage(File.join(FIXTURES, "mini.tmLanguage.json"))
    source = "def hello(name) # [ignored]\n\"str {x}\\n\"\n<<END\nbody()\nEND\n"
    tokens = names(lexer, source)

    assert_kind_of Rouge::Lexer, lexer
    assert_equal "mini", lexer.class.tag
    assert_equal source, tokens.map(&:last).join
    assert_includes tokens, ["Keyword", "def"]
    assert_includes tokens, ["Name.Function", "hello"]
    assert_includes tokens, ["Punctuation", "\""]
    assert tokens.any? { |token, text| token == "Comment" && text.include?("[ignored]") }
    assert tokens.any? { |token, text| token == "Literal.String" && text.include?("body()") }
    assert tokens.any? { |token, text| token == "Literal.String.Escape" && text == "\\n" }
  end

  def test_xml_plist_preserves_utf8_crlf_and_scope_mapping
    lexer = Antares::Grammar.load_tmlanguage(File.join(FIXTURES, "mini.tmLanguage.plist"))
    source = "TRUE\r\n\"é{}\"\r\n{}\r\n"
    tokens = names(lexer, source)

    assert_equal "miniplist", lexer.class.tag
    assert_equal source, tokens.map(&:last).join
    assert_includes tokens, ["Keyword.Constant", "TRUE"]
    assert tokens.any? { |token, text| token == "Literal.String" && text.include?("é{}") }
    assert_equal 1, tokens.count { |token, text| token == "Punctuation" && text == "{}" }

    xml = "<plist><dict><key>scopeName</key><string><![CDATA[source.cdata]]></string>" \
      "<key>patterns</key><array><dict><key>match</key><string><![CDATA[&]]></string>" \
      "</dict></array></dict></plist>"
    with_grammar(xml, ".plist") do |path|
      loaded = Antares::Grammar.load_tmlanguage(path)
      assert_equal "&", loaded.lex("&").map { |_token, text| text }.join
    end
  end

  def test_loaded_lexer_integrates_with_structure_and_edit_invalidation
    lexer = Antares::Grammar.load_tmlanguage(File.join(FIXTURES, "mini.tmLanguage.json"))
    lines = ["call(value) # [ignored]\n", "\"{ignored}\"\n"]
    highlighter = Antares::Highlighter.new(lexer: lexer, lines: ->(index) { lines[index] },
      line_count: -> { lines.length }, max_seconds: 2)
    structure = highlighter.structure

    assert_equal [[0, 4, 0, 10, 0, "()"]], structure.brackets.map(&:values)
    lines[0] = "call[value] # (ignored)\n"
    highlighter.edit(from_line: 0, removed: 1, inserted: 1)
    assert_same structure, highlighter.structure
    assert_equal [[0, 4, 0, 10, 0, "[]"]], structure.brackets.map(&:values)
  end

  def test_loaded_lexer_resource_limit_falls_back_to_complete_plain_text
    template = Antares::Grammar.load_tmlanguage(File.join(FIXTURES, "mini.tmLanguage.json"))
    lexer = template.class.new(max_bytes: 4)
    lines = ["complete text\n"]
    highlighter = Antares::Highlighter.new(lexer: lexer, lines: ->(index) { lines[index] },
      line_count: -> { lines.length })

    assert_equal "complete text\n", highlighter.tokens_for(0).map(&:last).join
    assert_match(/source exceeds/, highlighter.fallback_reason)
    refute Antares::Grammar.respond_to?(:parse)
  end

  def test_rejects_unsupported_or_malformed_grammar_constructs
    invalid = [
      {"scopeName" => "source.bad", "patterns" => [{"include" => "source.other"}]},
      {"scopeName" => "source.bad", "patterns" => [{"begin" => "x", "while" => "y"}]},
      {"scopeName" => "source.bad", "patterns" => [{"match" => "["}]},
      {"scopeName" => "source.bad", "patterns" => [{"match" => "x", "captures" => {"1" => {"patterns" => []}}}]},
      {"scopeName" => "source.bad", "patterns" => [{"include" => "#missing"}]}
    ]
    invalid.each do |grammar|
      with_grammar(JSON.generate(grammar)) do |path|
        assert_raises(Antares::GrammarError) { Antares::Grammar.load_tmlanguage(path) }
      end
    end

    with_grammar("{\"scopeName\":\"source.bad\",\"scopeName\":\"source.other\"}") do |path|
      assert_raises(Antares::GrammarError) { Antares::Grammar.load_tmlanguage(path) }
    end
    with_grammar("\xFF".b) do |path|
      assert_raises(Antares::GrammarError) { Antares::Grammar.load_tmlanguage(path) }
    end
    with_grammar("<!DOCTYPE plist [<!ENTITY x 'boom'>]><plist><string>&x;</string></plist>", ".plist") do |path|
      assert_raises(Antares::GrammarError) { Antares::Grammar.load_tmlanguage(path) }
    end
    with_grammar("<plist><dict><key>scopeName</key><string>source.bad</string><key>patterns</key><true>yes</true></dict></plist>", ".plist") do |path|
      assert_raises(Antares::GrammarError) { Antares::Grammar.load_tmlanguage(path) }
    end
  end

  def test_self_and_base_includes_reenter_root_patterns
    %w[$self $base].each do |target|
      grammar = {"scopeName" => "source.recursive", "patterns" => [
        {"match" => "\\bword\\b", "name" => "keyword"},
        {"begin" => "\\(", "end" => "\\)", "patterns" => [{"include" => target}]}
      ]}
      with_grammar(JSON.generate(grammar)) do |path|
        tokens = names(Antares::Grammar.load_tmlanguage(path), "(word)")
        assert_includes tokens, ["Keyword", "word"]
        assert_equal "(word)", tokens.map(&:last).join
      end
    end
  end

  def test_apply_end_pattern_last_gives_nested_pattern_tie_priority
    grammar = {"scopeName" => "source.end-last", "patterns" => [{
      "begin" => "<", "end" => ">", "name" => "string", "applyEndPatternLast" => true,
      "endCaptures" => {"0" => {"name" => "punctuation"}},
      "patterns" => [{"match" => "(?<=<)>", "name" => "keyword"}]
    }]}
    with_grammar(JSON.generate(grammar)) do |path|
      tokens = names(Antares::Grammar.load_tmlanguage(path), "<>>")
      assert_includes tokens, ["Keyword", ">"]
      assert_equal 1, tokens.count { |token, text| token == "Punctuation" && text == ">" }
    end
  end

  def test_bounds_file_nesting_include_recursion_and_runtime_progress
    with_grammar(" " * (Antares::Grammar::MAX_BYTES + 1)) do |path|
      assert_raises(Antares::ResourceLimitError) { Antares::Grammar.load_tmlanguage(path) }
    end

    oversized_regex = {"scopeName" => "source.regex", "patterns" => [
      {"match" => "x" * (Antares::Grammar::MAX_REGEX_BYTES + 1)}
    ]}
    with_grammar(JSON.generate(oversized_regex)) do |path|
      assert_raises(Antares::ResourceLimitError) { Antares::Grammar.load_tmlanguage(path) }
    end

    too_many_rules = {"scopeName" => "source.rules", "patterns" =>
      Array.new(Antares::Grammar::MAX_RULES + 1) { {"match" => "x"} }}
    with_grammar(JSON.generate(too_many_rules)) do |path|
      assert_raises(Antares::ResourceLimitError) { Antares::Grammar.load_tmlanguage(path) }
    end

    nested = {"patterns" => []}
    Antares::Grammar::MAX_DEPTH.times { nested = {"patterns" => [nested]} }
    nested["scopeName"] = "source.deep"
    with_grammar(JSON.generate(nested, max_nesting: false)) do |path|
      assert_raises(Antares::ResourceLimitError, Antares::GrammarError) { Antares::Grammar.load_tmlanguage(path) }
    end

    xml = "<plist>#{'<array>' * Antares::Grammar::MAX_DEPTH}<string>x</string>" \
      "#{'</array>' * Antares::Grammar::MAX_DEPTH}</plist>"
    with_grammar(xml, ".plist") do |path|
      assert_raises(Antares::ResourceLimitError) { Antares::Grammar.load_tmlanguage(path) }
    end

    recursive = {"scopeName" => "source.recursive", "patterns" => [{"include" => "#a"}],
      "repository" => {"a" => {"include" => "#b"}, "b" => {"include" => "#a"}}}
    with_grammar(JSON.generate(recursive)) do |path|
      lexer = Antares::Grammar.load_tmlanguage(path)
      assert_raises(Antares::ResourceLimitError) { lexer.lex("x").to_a }
    end

    repository = {}
    rule = {"match" => "x"}
    14.times do |index|
      repository["level#{index}"] = rule
      rule = {"patterns" => [
        {"include" => "#level#{index}"}, {"include" => "#level#{index}"}
      ]}
    end
    expansion = {"scopeName" => "source.expansion", "patterns" => rule["patterns"],
      "repository" => repository}
    with_grammar(JSON.generate(expansion)) do |path|
      lexer = Antares::Grammar.load_tmlanguage(path)
      assert_raises(Antares::ResourceLimitError) { lexer.lex("x").to_a }
    end

    contexts = {"scopeName" => "source.contexts", "patterns" => [
      {"begin" => "x", "end" => "z", "patterns" => [{"include" => "$self"}]}
    ]}
    with_grammar(JSON.generate(contexts)) do |path|
      lexer = Antares::Grammar.load_tmlanguage(path)
      assert_raises(Antares::ResourceLimitError) { lexer.lex("x" * 300).to_a }
    end

    zero_width = {"scopeName" => "source.zero", "patterns" => [{"match" => "(?=x)", "name" => "keyword"}]}
    with_grammar(JSON.generate(zero_width)) do |path|
      lexer = Antares::Grammar.load_tmlanguage(path)
      assert_raises(Antares::GrammarError) { lexer.lex("x").to_a }
    end

    missing_end_capture = {"scopeName" => "source.capture", "patterns" => [
      {"begin" => "x", "end" => "\\1"}
    ]}
    with_grammar(JSON.generate(missing_end_capture)) do |path|
      lexer = Antares::Grammar.load_tmlanguage(path)
      assert_raises(Antares::GrammarError) { lexer.lex("x").to_a }
    end
  end

  def test_bounds_regex_execution_and_validates_capture_indexes
    slow_rules = Array.new(50) { |index| {"match" => "never#{index}"} }
    slow_rules << {"match" => "."}
    grammar = {"scopeName" => "source.slow", "patterns" => slow_rules}
    with_grammar(JSON.generate(grammar)) do |path|
      template = Antares::Grammar.load_tmlanguage(path)
      lexer = template.class.new(max_seconds: 0.0001)
      assert_raises(Antares::ResourceLimitError) { lexer.lex("x" * 100_000).to_a }
    end

    capture = {"scopeName" => "source.capture", "patterns" => [
      {"match" => "x", "captures" => {"2" => {"name" => "keyword"}}}
    ]}
    with_grammar(JSON.generate(capture)) do |path|
      lexer = Antares::Grammar.load_tmlanguage(path)
      assert_raises(Antares::GrammarError) { lexer.lex("x").to_a }
    end
  end
end
