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

  def test_edit_reuses_the_structure_and_updates_only_the_changed_suffix
    lines = Array.new(10_000) { |index| "value_#{index} = #{index}\n" }
    highlighter = highlighter(lines, lexer: Rouge::Lexers::Python.new,
      strategy: :incremental, checkpoint_interval: 64)
    structure = highlighter.structure
    assert_empty structure.brackets
    line_before = structure.instance_variable_get(:@line_data)[9000]
    lines[5000] = "value_5000 = (5000)\n"
    highlighter.edit(from_line: 5000, removed: 1, inserted: 1)
    pair = structure.bracket_at(5000, 13)
    assert_equal [13, 18], [pair.open_column, pair.close_column]
    assert_same structure, highlighter.structure
    assert_same line_before, structure.instance_variable_get(:@line_data)[9000]
  end

  def test_rejects_invalid_positions_and_ranges
    structure = highlighter(["x\n"]).structure
    assert_raises(RangeError) { structure.bracket_at(1, 0) }
    assert_raises(ArgumentError) { structure.bracket_at(0, -1) }
    assert_raises(RangeError) { structure.fold_regions(0..1) }
  end
end
