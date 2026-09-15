# frozen_string_literal: true

require "test_helper"
require_relative "support/lexer_compatibility"

class HighlighterTest < Minitest::Test
  def highlighter(lines, lexer: Rouge::Lexers::Ruby.new, **options)
    Antares::Highlighter.new(lexer: lexer, lines: ->(index) { lines[index] }, line_count: -> { lines.length }, **options)
  end

  def names(rows) = rows.map { |row| row.map { |token, text| [token.qualname, text] } }

  def test_single_line_tokens_skip_empty_values_without_mutating_lexer_strings
    type = Rouge::Token::Tokens::Name
    source = "日本".freeze
    rows = highlighter([source]).send(:split_tokens, [[type, ""], [type, source], [type, "語\nlast"]], 0)
    assert_equal [["Name", "日本語\n"]], names([rows[0]]).first
    assert_equal [["Name", "last"]], names([rows[1]]).first
    assert_equal "日本", source
    assert rows[0].first.last.frozen?
  end

  def test_multiline_rules_are_identical_to_full_rouge_after_edits
    lines = ["=begin\n", "comment\n", "=end\n", "puts 42\n", ""]
    driver = highlighter(lines, strategy: :incremental, checkpoint_interval: 2)
    assert_equal LexerCompatibility.rows(Rouge::Lexers::Ruby.new, lines.join, lines.length), names(driver.tokens_in(0...lines.length))
    lines[1] = "another comment\n"
    driver.edit(from_line: 1, removed: 1, inserted: 1)
    assert_equal LexerCompatibility.rows(Rouge::Lexers::Ruby.new, lines.join, lines.length), names(driver.tokens_in(0...lines.length))
    assert_equal lines.length, driver.frontier
    assert_empty driver.tokens_for(4)
  end

  def test_incremental_convergence_reuses_untouched_suffix_and_sparse_checkpoints
    lines = Array.new(5000) { |index| "value_#{index} = #{index}\n" }
    driver = highlighter(lines, strategy: :incremental, max_seconds: 5)
    driver.advance(until_line: lines.length - 1)
    assert_operator driver.checkpoints.size, :<=, 81
    assert_operator driver.checkpoint_bytes, :<, 2_000_000
    untouched = driver.tokens_for(4999)
    lines[2496] = "value_2496 = 99\n"
    driver.edit(from_line: 2496, removed: 1, inserted: 1)
    driver.advance(until_line: 4999)
    assert_same untouched, driver.tokens_for(4999)
    assert_operator driver.last_scanned_lines, :<=, 3
    assert_equal LexerCompatibility.rows(Rouge::Lexers::Ruby.new, lines[2496], 1).first, names([driver.tokens_for(2496)]).first
  end

  def test_insert_delete_at_checkpoints_and_partial_lazy_frontier
    lines = Array.new(24) { |index| "puts #{index}\n" }
    driver = highlighter(lines, strategy: :incremental, checkpoint_interval: 4)
    driver.tokens_for(7)
    assert_equal 8, driver.frontier
    lines[4, 8] = ["text = <<~TEXT\n", "hello\n", "TEXT\n"]
    driver.edit(from_line: 4, removed: 8, inserted: 3)
    assert_equal LexerCompatibility.rows(Rouge::Lexers::Ruby.new, lines.join, lines.length), names(driver.tokens_in(0...lines.length))
    lines[0, 4] = []
    driver.edit(from_line: 0, removed: 4, inserted: 0)
    assert_equal LexerCompatibility.rows(Rouge::Lexers::Ruby.new, lines.join, lines.length), names(driver.tokens_in(0...lines.length))
  end

  def test_edit_updates_synthesized_final_line_separator
    lines = ["one"]
    driver = highlighter(lines, strategy: :incremental)
    assert_equal "one", driver.tokens_for(0).map(&:last).join

    lines << "two"
    driver.edit(from_line: 1, removed: 0, inserted: 1)
    assert_equal ["one\n", "two"], driver.tokens_in(0..1).map { |row| row.map(&:last).join }

    lines.pop
    driver.edit(from_line: 1, removed: 1, inserted: 0)
    assert_equal "one", driver.tokens_for(0).map(&:last).join
  end

  def test_full_window_unknown_lexer_and_provider_without_newlines
    lines = ["first = 1", "second = 2", ""]
    full = highlighter(lines, strategy: :full)
    assert_equal "first = 1\n", full.tokens_for(0).map(&:last).join
    assert_equal 3, full.frontier
    window = highlighter(lines, strategy: :window, window_context: 0)
    assert_equal "second = 2\n", window.tokens_for(1).map(&:last).join
    assert_equal ["first = 1\n", "second = 2\n", ""], window.tokens_in(0..2).map { |row| row.map(&:last).join }
    assert_equal :window, Antares.compatible?(Class.new(Rouge::Lexers::Ruby))
  end

  def test_line_provider_validation_accepts_one_separator_only
    assert_equal "name", highlighter(["name".encode(Encoding::US_ASCII)]).tokens_for(0).map(&:last).join
    assert_equal "name\r\n", highlighter(["name\r\n"]).tokens_for(0).map(&:last).join
    assert_raises(ArgumentError) { highlighter(["one\ntwo\n"]).tokens_for(0) }
    assert_raises(EncodingError) { highlighter(["\xFF".b]).tokens_for(0) }
  end

  def test_size_limits_fallback_without_truncating_text
    lines = ["x" * 100, "puts 1\n"]
    driver = highlighter(lines, strategy: :auto, max_line_bytes: 32)
    assert_equal lines.first + "\n", driver.tokens_for(0).map(&:last).join
    assert_equal :window, driver.strategy
    assert_operator driver.checkpoint_bytes, :<=, 1024
    assert_raises(RangeError) { driver.tokens_for(-1) }
    assert_raises(ArgumentError) { driver.edit(from_line: 0, removed: 1, inserted: 0) }
  end

  def test_snapshot_copies_nested_mutable_heredoc_state
    lexer = Rouge::Lexers::Ruby.new
    lexer.reset!
    lexer.continue_lex("text = <<~TEXT\n").to_a
    snapshot = Antares::LexerStateSnapshot.new(lexer)
    restored = snapshot.restore
    restored.instance_variable_get(:@heredoc_queue).first.last.replace("CHANGED")
    assert_equal "TEXT", lexer.instance_variable_get(:@heredoc_queue).first.last
    assert_equal "TEXT", snapshot.restore.instance_variable_get(:@heredoc_queue).first.last
  end

  def test_repeated_partial_edits_match_the_full_lexer
    [Rouge::Lexers::Python, Rouge::Lexers::Javascript, Rouge::Lexers::HTML, Rouge::Lexers::Rust].each do |klass|
      lines = LexerCompatibility.samples(klass)[1].lines
      random = Random.new(901)
      driver = highlighter(lines, lexer: klass.new, strategy: :incremental, checkpoint_interval: 4)
      35.times do |iteration|
        index = random.rand(lines.length) unless lines.empty?
        if index && !lines.empty?
          expected = LexerCompatibility.rows(klass.new, lines.join, lines.length)
          assert_equal expected[index], names([driver.tokens_for(index)]).first, "#{klass.tag}, partial #{iteration}"
        end
        first, removed, inserted = LexerCompatibility.mutate(lines, random, iteration)
        driver.edit(from_line: first, removed: removed, inserted: inserted)
      end
      assert_equal LexerCompatibility.rows(klass.new, lines.join, lines.length), names(driver.tokens_in(0...lines.length)), klass.tag
    end
  end

  def test_timeout_and_byte_ceiling_return_complete_plain_text
    slow = Class.new(Rouge::RegexLexer) do
      state :root do
        rule(/.+/m) { |match| sleep 0.05; token Text, match[0] }
      end
    end
    lines = ["unchanged text\n"]
    driver = highlighter(lines, lexer: slow.new, strategy: :full, max_seconds: 0.005)
    assert_equal lines, driver.tokens_in(0..0).map { |row| row.map(&:last).join }
    assert_equal :window, driver.strategy
    assert_match(/exceeded/, driver.fallback_reason)
    bounded = highlighter(lines, strategy: :full, max_bytes: 4)
    assert_equal lines.first, bounded.tokens_for(0).map(&:last).join
    assert_equal :window, bounded.strategy
  end
end
