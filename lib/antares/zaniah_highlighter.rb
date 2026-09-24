# frozen_string_literal: true

require_relative "../antares"

module Antares
  # Optional CodeEditor highlighter; load with require "antares/zaniah_highlighter".
  class ZaniahHighlighter
    def initialize(lexer:, buffer:)
      unless buffer.respond_to?(:line_count) && buffer.respond_to?(:line)
        raise ArgumentError, "buffer must provide line_count and line"
      end
      @buffer = buffer
      @snapshot = lines
      @highlighter = Highlighter.new(lexer: lexer,
        lines: ->(index) { @buffer.line(index) }, line_count: -> { @buffer.line_count })
    end

    def tokens(index, text)
      raise TypeError, "line text must be a String" unless text.is_a?(String)
      return [] if text.empty?

      offset = 0
      @highlighter.tokens_for(index).filter_map do |kind, value|
        first = offset
        offset += value.bytesize
        last = [offset, text.bytesize].min
        [first...last, scope(kind)].freeze if last > first
      end
    end

    def edited(_range, _replacement)
      updated = lines
      old = @snapshot
      first = 0
      first += 1 while first < old.length && first < updated.length && old[first] == updated[first]
      old_end, new_end = old.length, updated.length
      while old_end > first && new_end > first && old[old_end - 1] == updated[new_end - 1]
        old_end -= 1
        new_end -= 1
      end
      @highlighter.edit(from_line: first, removed: old_end - first, inserted: new_end - first) if
        old_end != first || new_end != first
      @snapshot = updated
      self
    end

    private

    # ponytail: snapshots scan all lines after edits; incremental line deltas can replace this if large-buffer editing profiles slow.
    def lines = Array.new(@buffer.line_count) { |index| @buffer.line(index).dup.freeze }

    def scope(kind)
      name = kind&.qualname.to_s
      case name
      when /\AKeyword/ then :keyword
      when /\ALiteral\.String/ then :string
      when /\ALiteral\.Number/ then :number
      when /\AComment/ then :comment
      when /\AName\.(Function|Builtin)/ then :function
      when /\AName\.(Class|Namespace|Decorator)/ then :type
      when /\AName\.Constant/ then :constant
      when /\AName\.Variable/ then :variable
      when /\AOperator/ then :operator
      when /\APunctuation/ then :punctuation
      else :text
      end
    end
  end
end
