# frozen_string_literal: true

require_relative "test_helper"
require "antares/zaniah_highlighter"

class ZaniahHighlighterTest < Minitest::Test
  Buffer = Struct.new(:rows) do
    def line_count = rows.length
    def line(index) = rows.fetch(index)
  end

  def test_maps_rouge_tokens_to_syntax_scopes_with_byte_ranges
    buffer = Buffer.new(["def greet", "  42"])
    adapter = Antares::ZaniahHighlighter.new(lexer: Rouge::Lexers::Ruby.new, buffer: buffer)

    assert_includes adapter.tokens(0, buffer.line(0)), [0...3, :keyword]
    assert_includes adapter.tokens(0, buffer.line(0)), [4...9, :function]
    assert_includes adapter.tokens(1, buffer.line(1)), [2...4, :number]
  end

  def test_rechecks_changed_lines_after_an_edit
    buffer = Buffer.new([+"value = 1", "puts value"])
    adapter = Antares::ZaniahHighlighter.new(lexer: Rouge::Lexers::Ruby.new, buffer: buffer)
    adapter.tokens(1, buffer.line(1))

    buffer.rows[0].replace("value = 'two'")
    adapter.edited(8...9, "'two'")

    assert_includes adapter.tokens(0, buffer.line(0)), [8...13, :string]
  end
end
