# frozen_string_literal: true

module Antares
  Bracket = Struct.new(:open_line, :open_column, :close_line, :close_column,
    :depth, :kind, keyword_init: true)
  Region = Struct.new(:start_line, :end_line, :kind, :label,
    :start_column, :end_column, keyword_init: true)

  class Structure
    OPEN = {"(" => ")", "[" => "]", "{" => "}"}.freeze
    CLOSE = OPEN.invert.freeze
    REGION_MARKER = /\A\s*(?:\#|\/\/|\/\*+|<!--)\s*\#?\s*(end)?region\b/i
    Line = Struct.new(:text, :tokens, :brackets, :spans, :indent, :blank,
      :comment, :marker, :label, keyword_init: true)

    def initialize(lines:, line_count:, tokens_for:, tokens_in:)
      @lines = lines
      @line_count = line_count
      @tokens_for = tokens_for
      @tokens_in = tokens_in
      @line_data = []
      @dirty_from = 0
      @indexes_dirty = true
    end

    def fold_regions(range = nil)
      refresh
      select_range(@fold_regions, range) { |region| [region.start_line, region.end_line] }
    end

    def brackets(range = nil)
      refresh
      select_range(@brackets, range) { |bracket| [bracket.open_line, bracket.close_line] }
    end

    def bracket_at(line, column)
      validate_position(line, column)
      refresh
      @bracket_positions[[line, column]]
    end

    def context_at(line)
      validate_line(line)
      refresh
      @fold_regions.select { |region| region.start_line <= line && line <= region.end_line }
        .sort_by { |region| [region.start_line, -region.end_line] }
    end

    def selection_ranges(line, column)
      validate_position(line, column)
      refresh
      ranges = []
      token = @line_data.fetch(line).spans.find { |span| span[0] <= column && column < span[1] }
      ranges << selection_region(line, token) if token
      containing_brackets(line, column).each do |bracket|
        ranges << Region.new(start_line: bracket.open_line, end_line: bracket.close_line,
          start_column: bracket.open_column + 1, end_column: bracket.close_column,
          kind: :block, label: "inside #{bracket.kind}")
        ranges << Region.new(start_line: bracket.open_line, end_line: bracket.close_line,
          start_column: bracket.open_column, end_column: bracket.close_column + 1,
          kind: :block, label: bracket.kind)
      end
      ranges << Region.new(start_line: line, end_line: line, start_column: 0,
        end_column: @line_data.fetch(line).text.delete_suffix("\n").length,
        kind: :line, label: @line_data.fetch(line).label)
      ranges.concat(context_at(line).reverse)
      ranges.uniq { |region| [region.start_line, region.start_column, region.end_line, region.end_column] }
    end

    # The provider must already reflect the edit, matching Highlighter#edit.
    def edit(from_line:, removed:, inserted:)
      @line_data[from_line, removed] = Array.new(inserted)
      @dirty_from = [@dirty_from || from_line, from_line].min
      @indexes_dirty = true
      self
    end

    private

    def refresh
      count = line_count
      if @line_data.length != count
        @line_data.fill(nil, @line_data.length...count) if @line_data.length < count
        @line_data.slice!(count..) if @line_data.length > count
      end
      refresh_lines(count) if @dirty_from
      rebuild_indexes if @indexes_dirty
      self
    end

    def refresh_lines(count)
      start = @dirty_from
      if start.zero? && @line_data.none?
        @tokens_in.call(0...count).each_with_index { |tokens, index| @line_data[index] = scan_line(index, tokens) }
        @dirty_from = nil
        return
      end
      index = start
      while index < count
        tokens = @tokens_for.call(index)
        previous = @line_data[index]
        break if index > start && previous && (previous.tokens.equal?(tokens) || previous.tokens == tokens)
        @line_data[index] = scan_line(index, tokens)
        index += 1
      end
      @dirty_from = nil
    end

    def scan_line(index, tokens)
      text = @lines.call(index)
      column = 0
      brackets = []
      spans = []
      significant = []
      tokens.each do |type, value|
        finish = column + value.length
        name = type.qualname
        unless value.strip.empty?
          significant << name
          kind = name.start_with?("Comment") ? :comment : (name.start_with?("Literal.String") ? :string : :token)
          spans << [column, finish, kind, value.delete_suffix("\n")]
        end
        if name.start_with?("Punctuation")
          value.each_char.with_index { |character, offset| brackets << [character, column + offset] if OPEN.key?(character) || CLOSE.key?(character) }
        end
        column = finish
      end
      stripped = text.strip
      comment = !significant.empty? && significant.all? { |name| name.start_with?("Comment") }
      marker = comment && (match = REGION_MARKER.match(text)) ? (match[1] ? :close : :open) : nil
      Line.new(text: text, tokens: tokens, brackets: brackets.freeze, spans: spans.freeze,
        indent: indentation(text), blank: stripped.empty?, comment: comment,
        marker: marker, label: stripped.freeze).freeze
    end

    def rebuild_indexes
      @brackets = build_brackets.freeze
      @bracket_positions = {}
      @brackets.each do |bracket|
        @bracket_positions[[bracket.open_line, bracket.open_column]] = bracket
        @bracket_positions[[bracket.close_line, bracket.close_column]] = bracket
      end
      regions = bracket_regions + derived_regions
      @fold_regions = regions.uniq { |region| [region.start_line, region.end_line, region.kind] }
        .sort_by { |region| [region.start_line, -region.end_line, region.kind.to_s] }.freeze
      @indexes_dirty = false
    end

    def build_brackets
      stack = []
      pairs = []
      @line_data.each_with_index do |line, line_index|
        line.brackets.each do |character, column|
          if OPEN.key?(character)
            stack << [character, line_index, column, stack.length]
          elsif stack.last&.first == CLOSE.fetch(character)
            open, open_line, open_column, depth = stack.pop
            pairs << Bracket.new(open_line: open_line, open_column: open_column,
              close_line: line_index, close_column: column, depth: depth,
              kind: "#{open}#{character}").freeze
          end
        end
      end
      pairs.sort_by { |bracket| [bracket.open_line, bracket.open_column] }
    end

    def bracket_regions
      @brackets.filter_map do |bracket|
        next if bracket.open_line == bracket.close_line
        Region.new(start_line: bracket.open_line, end_line: bracket.close_line,
          kind: :block, label: @line_data.fetch(bracket.open_line).label).freeze
      end
    end

    def derived_regions
      regions = []
      indentation = []
      markers = []
      comment_start = nil
      previous = nil
      bracket_starts = @brackets.each_with_object({}) do |bracket, starts|
        starts[bracket.open_line] = true if bracket.open_line < bracket.close_line
      end
      @line_data.each_with_index do |line, index|
        if line.comment && !line.marker
          comment_start ||= index
        else
          add_region(regions, comment_start, index - 1, :comment, @line_data.fetch(comment_start).label) if comment_start
          comment_start = nil
        end
        markers << [index, line.label] if line.marker == :open
        if line.marker == :close && markers.any?
          start_line, label = markers.pop
          add_region(regions, start_line, index, :region, label)
        end
        unless line.blank
          while indentation.last && line.indent < indentation.last[2]
            start_line, label, = indentation.pop
            add_region(regions, start_line, previous[0], :block, label)
          end
          if previous && line.indent > previous[1] && !previous[3] && !bracket_starts[previous[0]]
            indentation << [previous[0], previous[2], line.indent]
          end
          previous = [index, line.indent, line.label, line.comment]
        end
      end
      add_region(regions, comment_start, @line_data.length - 1, :comment,
        @line_data.fetch(comment_start).label) if comment_start
      indentation.reverse_each do |start_line, label, _|
        add_region(regions, start_line, previous[0], :block, label)
      end if previous
      regions
    end

    def add_region(regions, start_line, end_line, kind, label)
      return unless start_line && end_line > start_line
      regions << Region.new(start_line: start_line, end_line: end_line,
        kind: kind, label: label).freeze
    end

    def containing_brackets(line, column)
      @brackets.select do |bracket|
        ([bracket.open_line, bracket.open_column] <=> [line, column]) <= 0 &&
          ([line, column] <=> [bracket.close_line, bracket.close_column]) <= 0
      end.sort_by { |bracket| -bracket.depth }
    end

    def selection_region(line, span)
      Region.new(start_line: line, end_line: line, start_column: span[0],
        end_column: span[1], kind: span[2], label: span[3])
    end

    def select_range(values, range)
      return values.dup unless range
      first, last = range_bounds(range)
      values.select do |value|
        value_first, value_last = yield(value)
        value_last >= first && value_first <= last
      end
    end

    def range_bounds(range)
      raise ArgumentError, "range must have integer bounds" unless range.is_a?(Range) && range.begin.is_a?(Integer) && range.end.is_a?(Integer)
      last = range.exclude_end? ? range.end - 1 : range.end
      raise RangeError, "range outside document" if range.begin.negative? || last >= line_count
      [range.begin, last]
    end

    def validate_position(line, column)
      validate_line(line)
      raise ArgumentError, "column must be a nonnegative integer" unless column.is_a?(Integer) && column >= 0
    end

    def validate_line(line)
      raise RangeError, "line outside document" unless line.is_a?(Integer) && line >= 0 && line < line_count
    end

    def line_count
      value = @line_count.call
      raise ArgumentError, "line_count must return a nonnegative integer" unless value.is_a?(Integer) && value >= 0
      value
    end

    def indentation(text)
      column = 0
      text.each_char do |character|
        case character
        when " " then column += 1
        when "\t" then column += 8 - (column % 8)
        else break
        end
      end
      column
    end
  end
end
