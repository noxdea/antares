# frozen_string_literal: true

require "test_helper"

class StructureTest < Minitest::Test
  FIXTURES = {
    "ruby" => Rouge::Lexers::Ruby,
    "javascript" => Rouge::Lexers::Javascript,
    "python" => Rouge::Lexers::Python,
    "json" => Rouge::Lexers::JSON,
    "markdown" => Rouge::Lexers::Markdown
  }.freeze

  def highlighter(lines, lexer: Rouge::Lexers::Ruby.new, **options)
    Antares::Highlighter.new(lexer: lexer, lines: ->(index) { lines[index] },
      line_count: -> { lines.length }, max_seconds: 5, **options)
  end

  def render(structure)
    brackets = structure.brackets.map do |bracket|
      "#{bracket.open_line}:#{bracket.open_column}-#{bracket.close_line}:#{bracket.close_column} depth=#{bracket.depth} kind=#{bracket.kind}"
    end
    folds = structure.fold_regions.map do |region|
      "#{region.start_line}-#{region.end_line} kind=#{region.kind} label=#{region.label}"
    end
    (["brackets:"] + brackets + ["folds:"] + folds).join("\n") + "\n"
  end

  def test_language_structure_goldens
    FIXTURES.each do |name, lexer|
      source = File.read(File.join(__dir__, "fixtures/structure/#{name}.source"), encoding: Encoding::UTF_8)
      lines = source.lines
      actual = render(highlighter(lines, lexer: lexer.new).structure)
      expected = File.binread(File.join(__dir__, "fixtures/structure/#{name}.golden"))
      assert_equal expected, actual, name
    end
  end

  def test_bracket_lookup_context_and_selection_ranges
    lines = ["def call(value)\n", "  if value\n", "    puts(value)\n", "  end\n", "end\n"]
    structure = highlighter(lines).structure
    pair = structure.bracket_at(0, 8)
    assert_equal [0, 8, 0, 14, 0, "()"], pair.values
    assert_same pair, structure.bracket_at(0, 14)
    assert_equal [[0, 3], [1, 2]], structure.context_at(2).map { |region| [region.start_line, region.end_line] }
    ranges = structure.selection_ranges(2, 9)
    assert_equal :token, ranges.first.kind
    assert_equal [2, 9, 2, 14], [ranges.first.start_line, ranges.first.start_column,
      ranges.first.end_line, ranges.first.end_column]
    assert_equal [:token, :block, :line, :block, :block], ranges.map(&:kind)
  end

  def test_ignores_string_comment_and_mismatched_brackets_with_character_columns
    lines = ["😀 = \"(string)\" # [comment]\n", "é(値)\n", "(])\n"]
    structure = highlighter(lines).structure
    assert_equal [[1, 1, 1, 3, 0, "()"]], structure.brackets.map(&:values)
    assert_raises(RangeError) { structure.bracket_at(1, 5) }
  end

  def test_selection_token_does_not_include_the_line_separator
    structure = highlighter(["value\n"]).structure
    ranges = structure.selection_ranges(0, 2)
    token = ranges.first
    assert_equal [0, 0, 0, 5], [token.start_line, token.start_column, token.end_line, token.end_column]
    assert_equal 1, ranges.length
  end

  def test_edit_reuses_the_structure_and_updates_only_the_changed_suffix
    lines = Array.new(10_000) { |index| "value_#{index} = #{index}\n" }
    highlighter = highlighter(lines, lexer: Rouge::Lexers::Python.new,
      strategy: :incremental, checkpoint_interval: 64)
    structure = highlighter.structure
    assert_empty structure.brackets
    assert_empty structure.fold_regions
    derived_before = structure.instance_variable_get(:@derived_regions)
    line_before = structure.instance_variable_get(:@line_data)[9000]
    lines[5000] = "value_5000 = (5000)\n"
    highlighter.edit(from_line: 5000, removed: 1, inserted: 1)
    assert_empty structure.fold_regions
    assert_same derived_before, structure.instance_variable_get(:@derived_regions)
    pair = structure.bracket_at(5000, 13)
    assert_equal [13, 18], [pair.open_column, pair.close_column]
    assert_same structure, highlighter.structure
    assert_same line_before, structure.instance_variable_get(:@line_data)[9000]
  end

  def test_incremental_structure_matches_a_fresh_analysis_after_local_edits
    original = ["# region alpha\n", "def call(value)\n", "  if value\n", "    list = [\n",
      "      value,\n", "    ]\n", "  end\n", "end\n", "# endregion\n"]
    replacements = [[0, "# region beta\n"], [1, "def renamed(value)\n"],
      [2, "  unless value\n"], [3, "    items = [\n"], [3, "    list = []\n"],
      [4, "      (value),\n"], [5, "    }\n"], [8, "# trailing comment\n"]]

    replacements.each do |line, replacement|
      lines = original.dup
      edited = highlighter(lines, strategy: :incremental, checkpoint_interval: 2)
      render(edited.structure)
      lines[line] = replacement
      edited.edit(from_line: line, removed: 1, inserted: 1)

      assert_equal render(highlighter(lines).structure), render(edited.structure), "edit at line #{line}"
    end
  end

  def test_edit_rebuilds_derived_regions_when_a_region_label_changes
    lines = ["parent\n", "  child\n", "tail\n"]
    highlighter = highlighter(lines)
    structure = highlighter.structure
    assert_equal ["parent"], structure.fold_regions.map(&:label)
    derived_before = structure.instance_variable_get(:@derived_regions)

    lines[0] = "renamed\n"
    highlighter.edit(from_line: 0, removed: 1, inserted: 1)

    assert_equal ["renamed"], structure.fold_regions.map(&:label)
    refute_same derived_before, structure.instance_variable_get(:@derived_regions)
  end

  def test_edit_waits_for_lexer_state_convergence
    lines = ["text = <<A\n", "same\n", "A\n", "call()\n", "B\n"]
    highlighter = highlighter(lines, strategy: :incremental, checkpoint_interval: 2)
    structure = highlighter.structure
    assert_equal [[3, 4, 3, 5, 0, "()"]], structure.brackets.map(&:values)

    lines[0] = "text = <<B\n"
    highlighter.edit(from_line: 0, removed: 1, inserted: 1)

    assert_empty structure.brackets
  end

  def test_registered_language_provider_is_selected_and_receives_edits
    provider = Class.new(Antares::Structure) do
      attr_reader :edits

      def initialize(**arguments)
        super
        @edits = []
      end

      def edit(**change)
        @edits << change
        super
      end
    end
    Antares::Structure.register(:ruby, provider)
    lines = ["call()\n"]
    ruby = highlighter(lines)
    structure = ruby.structure

    assert_instance_of provider, structure
    assert_instance_of Antares::Structure, highlighter(lines, lexer: Rouge::Lexers::Python.new).structure
    lines[0] = "other()\n"
    ruby.edit(from_line: 0, removed: 1, inserted: 1)
    assert_equal [{from_line: 0, removed: 1, inserted: 1}], structure.edits
    assert_equal [0, 5, 0, 6, 0, "()"], structure.brackets.first.values
  ensure
    assert_same provider, Antares::Structure.unregister("RUBY") if provider
  end

  def test_structure_provider_contract_is_checked_on_use
    provider = Class.new do
      def initialize(**_arguments); end
    end
    Antares::Structure.register(:ruby, provider)

    error = assert_raises(Antares::Error) { highlighter(["x\n"]).structure }
    assert_match(/fold_regions/, error.message)
  ensure
    Antares::Structure.unregister(:ruby)
  end

  def test_rejects_invalid_positions_and_ranges
    structure = highlighter(["x\n"]).structure
    assert_raises(RangeError) { structure.bracket_at(1, 0) }
    assert_raises(ArgumentError) { structure.bracket_at(0, -1) }
    assert_raises(RangeError) { structure.fold_regions(0..1) }
    assert_raises(RangeError) { structure.fold_regions(0...-1) }
    assert_empty structure.fold_regions(1...1)

    invalid = Antares::Structure.new(lines: ->(_index) { "x\n" }, line_count: -> { 2 },
      tokens_for: ->(_index) { [] }, tokens_in: ->(_range) { [[], []] }, stabilize: ->(_line) { -1 })
    invalid.brackets
    invalid.edit(from_line: 1, removed: 1, inserted: 1)
    assert_raises(ArgumentError) { invalid.brackets }
  end
end
