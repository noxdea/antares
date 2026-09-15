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
    PROVIDER_METHODS = %i[fold_regions brackets bracket_at context_at selection_ranges edit].freeze
    Line = Struct.new(:text, :tokens, :brackets, :indent, :blank,
      :comment, :marker, :label, keyword_init: true)

    @providers = {}
    @providers_lock = Mutex.new

    class << self
      def register(language, provider)
        raise ArgumentError, "provider must respond to new" unless provider.respond_to?(:new)

        @providers_lock.synchronize { @providers[language_key(language)] = provider }
        provider
      end

      def unregister(language)
        @providers_lock.synchronize { @providers.delete(language_key(language)) }
      end

      def build(language:, **arguments)
        provider = language && @providers_lock.synchronize { @providers[language_key(language)] }
        structure = (provider || self).new(**arguments)
        missing = PROVIDER_METHODS.reject { |method| structure.respond_to?(method) }
        raise Error, "structure provider is missing #{missing.join(', ')}" unless missing.empty?

        structure
      end

      private

      def language_key(language)
        raise ArgumentError, "language must be a String or Symbol" unless language.is_a?(String) || language.is_a?(Symbol)

        value = language.to_s.downcase
        raise ArgumentError, "language must be nonempty" if value.empty? || value.include?("\0")

        value.freeze
      end
    end

    def initialize(lines:, line_count:, tokens_for:, tokens_in:, stabilize: nil)
      @lines = lines
      @line_count = line_count
      @tokens_for = tokens_for
      @tokens_in = tokens_in
      @stabilize = stabilize
      @line_data = []
      @dirty_from = 0
      @brackets_dirty = true
      @folds_dirty = true
      @fold_brackets_dirty = true
      @derived_dirty = true
      @derived_regions = [].freeze
      @fold_start_lines = {}.freeze
      @pending_old_lines = nil
      @token_kinds = {}
    end

    def fold_regions(range = nil)
      refresh(folds: true)
      select_range(@fold_regions, range) { |region| [region.start_line, region.end_line] }
    end

    def brackets(range = nil)
      refresh(brackets: true)
      select_range(@brackets, range) { |bracket| [bracket.open_line, bracket.close_line] }
    end

    def bracket_at(line, column)
      validate_position(line, column, brackets: true)
      @bracket_positions[[line, column]]
    end

    def context_at(line)
      validate_line(line)
      refresh(folds: true)
      @fold_regions.select { |region| region.start_line <= line && line <= region.end_line }
        .sort_by { |region| [region.start_line, -region.end_line] }
    end

    def selection_ranges(line, column)
      validate_position(line, column, brackets: true, folds: true)
      ranges = []
      token = selection_spans(@line_data.fetch(line)).find { |span| span[0] <= column && column < span[1] }
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
      if @pending_old_lines || removed != inserted
        @folds_dirty = @fold_brackets_dirty = @derived_dirty = true
        @pending_old_lines = nil
      else
        @pending_old_lines = [from_line, @line_data.slice(from_line, removed) || []]
      end
      @line_data[from_line, removed] = Array.new(inserted)
      @dirty_from = [@dirty_from || from_line, from_line].min
      @brackets_dirty = true
      if removed != inserted
        @folds_dirty = true
        @fold_brackets_dirty = true
      end
      self
    end

    private

    def refresh(brackets: false, folds: false)
      count = line_count
      if @line_data.length != count
        @brackets_dirty = @folds_dirty = @fold_brackets_dirty = @derived_dirty = true
        @line_data.fill(nil, @line_data.length...count) if @line_data.length < count
        @line_data.slice!(count..) if @line_data.length > count
      end
      refresh_lines(count) if @dirty_from
      rebuild_brackets if brackets && @brackets_dirty
      if folds && @folds_dirty
        rebuild_brackets if @fold_brackets_dirty && @brackets_dirty
        rebuild_folds
      end
      self
    end

    def refresh_lines(count)
      start = @dirty_from
      if start.zero? && @line_data.none?
        @tokens_in.call(0...count).each_with_index { |tokens, index| @line_data[index] = scan_line(index, tokens) }
        @dirty_from = nil
        return
      end
      finish = @stabilize ? @stabilize.call(start) : count
      unless finish.is_a?(Integer) && finish >= start && finish <= count
        raise ArgumentError, "stabilize must return a line boundary inside the document"
      end
      index = start
      while index < finish
        tokens = @tokens_for.call(index)
        old = old_line(index)
        updated = scan_line(index, tokens)
        if bracket_boundary_changed?(old, updated)
          @fold_brackets_dirty = @folds_dirty = @derived_dirty = true
        end
        if derived_line_changed?(old, updated, index)
          @folds_dirty = @derived_dirty = true
        end
        @line_data[index] = updated
        index += 1
      end
      @pending_old_lines = nil
      @dirty_from = nil
    end

    def scan_line(index, tokens)
      text = @lines.call(index)
      column = 0
      brackets = []
      significant = false
      comment = true
      tokens.each do |type, value|
        finish = column + value.length
        token_kind = @token_kinds[type] ||= classify_token(type.qualname)
        if comment && !value.strip.empty?
          significant = true
          comment = token_kind == :comment
        end
        if token_kind == :punctuation
          value.each_char.with_index { |character, offset| brackets << [character, column + offset] if OPEN.key?(character) || CLOSE.key?(character) }
        end
        column = finish
      end
      stripped = text.strip
      comment &&= significant
      marker = comment && (match = REGION_MARKER.match(text)) ? (match[1] ? :close : :open) : nil
      Line.new(text: text, tokens: tokens, brackets: brackets.freeze,
        indent: indentation(text), blank: stripped.empty?, comment: comment,
        marker: marker, label: stripped.freeze).freeze
    end

    def rebuild_brackets
      @brackets = build_brackets.freeze
      @bracket_positions = {}
      @brackets.each do |bracket|
        @bracket_positions[[bracket.open_line, bracket.open_column]] = bracket
        @bracket_positions[[bracket.close_line, bracket.close_column]] = bracket
      end
      @brackets_dirty = false
    end

    def rebuild_folds
      if @derived_dirty
        @derived_regions = derived_regions.freeze
      end
      regions = bracket_regions + @derived_regions
      @fold_regions = regions.uniq { |region| [region.start_line, region.end_line, region.kind] }
        .sort_by { |region| [region.start_line, -region.end_line, region.kind.to_s] }.freeze
      @fold_start_lines = @fold_regions.each_with_object({}) do |region, starts|
        starts[region.start_line] = true
      end.freeze
      @derived_dirty = false
      @folds_dirty = @fold_brackets_dirty = false
    end

    def old_line(index)
      return @line_data[index] unless @pending_old_lines

      first, lines = @pending_old_lines
      index >= first && index < first + lines.length ? lines[index - first] : @line_data[index]
    end

    def derived_line_changed?(old, updated, index)
      return true unless old
      return false if old.equal?(updated)
      return true unless old.indent == updated.indent && old.blank == updated.blank &&
        old.comment == updated.comment && old.marker == updated.marker

      old.label != updated.label && @fold_start_lines.key?(index)
    end

    def bracket_boundary_changed?(old, updated)
      return true unless old
      return false if old.brackets == updated.brackets

      !locally_balanced?(old.brackets) || !locally_balanced?(updated.brackets)
    end

    def locally_balanced?(brackets)
      stack = []
      brackets.each do |character, _column|
        if OPEN.key?(character)
          stack << character
        elsif stack.last == CLOSE.fetch(character)
          stack.pop
        else
          return false
        end
      end
      stack.empty?
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
          else
            stack.pop
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

    def selection_spans(line)
      column = 0
      line.tokens.filter_map do |type, value|
        span = nil
        finish = column + value.length
        unless value.strip.empty?
          token_kind = @token_kinds[type] ||= classify_token(type.qualname)
          kind = token_kind == :comment ? :comment : (token_kind == :string ? :string : :token)
          span_finish = value.end_with?("\n") ? finish - 1 : finish
          span = [column, span_finish, kind, value.delete_suffix("\n")] if span_finish > column
        end
        column = finish
        span
      end
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
      count = line_count
      last = range.exclude_end? ? range.end - 1 : range.end
      endpoints = [range.begin, range.end]
      outside = endpoints.any?(&:negative?) || endpoints.any? { |value| value > count }
      outside ||= !range.exclude_end? && endpoints.include?(count)
      raise RangeError, "range outside document" if outside
      [range.begin, last]
    end

    def validate_position(line, column, brackets: false, folds: false)
      validate_line(line)
      raise ArgumentError, "column must be a nonnegative integer" unless column.is_a?(Integer) && column >= 0
      refresh(brackets: brackets, folds: folds)
      text = @line_data.fetch(line).text
      last = text.end_with?("\n") ? text.length - 1 : text.length
      raise RangeError, "column outside line" if column > last
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

    def comment_token?(name) = name == "Comment" || name.start_with?("Comment.")
    def string_token?(name) = name == "Literal.String" || name.start_with?("Literal.String.")
    def punctuation_token?(name) = name == "Punctuation" || name.start_with?("Punctuation.")

    def classify_token(name)
      return :comment if comment_token?(name)
      return :string if string_token?(name)
      return :punctuation if punctuation_token?(name)

      :token
    end
  end
end
