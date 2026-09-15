# frozen_string_literal: true

require "timeout"

module Antares
  class Highlighter
    STRATEGIES = %i[auto incremental window full].freeze
    attr_reader :strategy, :requested_strategy, :frontier, :checkpoints, :last_scanned_lines, :fallback_reason

    def initialize(lexer:, lines:, line_count:, strategy: :auto, checkpoint_interval: 64,
      window_context: 200, max_bytes: 8 * 1024 * 1024, max_lines: 100_000,
      max_line_bytes: 16_384, max_checkpoint_bytes: 256 * 1024, max_seconds: 0.25)
      raise ArgumentError, "unknown strategy #{strategy.inspect}" unless STRATEGIES.include?(strategy)
      raise ArgumentError, "lines and line_count must be callable" unless lines.respond_to?(:call) && line_count.respond_to?(:call)
      {checkpoint_interval: checkpoint_interval, max_bytes: max_bytes, max_lines: max_lines,
        max_line_bytes: max_line_bytes, max_checkpoint_bytes: max_checkpoint_bytes}.each do |name, value|
        raise ArgumentError, "#{name} must be a positive integer" unless value.is_a?(Integer) && value.positive?
      end
      raise ArgumentError, "window_context must be nonnegative" unless window_context.is_a?(Integer) && window_context >= 0
      raise ArgumentError, "max_seconds must be positive" unless max_seconds.is_a?(Numeric) && max_seconds.positive?
      @template = lexer
      @lines, @line_count = lines, line_count
      @requested_strategy = strategy
      @strategy = strategy == :auto ? Antares.compatible?(lexer) : strategy
      @checkpoint_interval, @window_context = checkpoint_interval, window_context
      @max_bytes, @max_lines, @max_line_bytes = max_bytes, max_lines, max_line_bytes
      @max_checkpoint_bytes, @max_seconds = max_checkpoint_bytes, max_seconds
      @tokens, @fingerprints, @checkpoints = {}, {}, {}
      @frontier = @last_scanned_lines = 0
      @count = count
      @dirty_until = 0
      initialize_lexer
    rescue UnsupportedLexerError => error
      raise unless strategy == :auto || strategy == :window || strategy == :full
      @template = lexer
      @strategy = :window if strategy == :auto
      @fallback_reason = error.message
    end

    def tokens_for(index)
      validate_index(index)
      advance(until_line: index) unless @tokens.key?(index) && index < frontier
      @tokens.fetch(index) { plain(index) }
    end

    def tokens_in(range)
      indexes = range.to_a
      return [] if indexes.empty?
      indexes.each { |index| validate_index(index) }
      advance(until_line: indexes.max, from_line: indexes.min)
      indexes.map { |index| @tokens.fetch(index) { plain(index) } }
    end

    def structure
      @structure ||= Structure.new(
        lines: @lines,
        line_count: @line_count,
        tokens_for: method(:tokens_for),
        tokens_in: method(:tokens_in),
        stabilize: method(:stabilize_structure)
      )
    end

    # Provider contents must already reflect this line edit. Indices are zero based.
    def edit(from_line:, removed:, inserted:)
      values = [from_line, removed, inserted]
      raise ArgumentError, "edit fields must be nonnegative integers" unless values.all? { |value| value.is_a?(Integer) && value >= 0 }
      raise RangeError, "edit outside previous document" unless from_line <= @count && from_line + removed <= @count
      updated_count = count
      raise ArgumentError, "line_count disagrees with edit" unless updated_count == @count - removed + inserted
      @last_scanned_lines = 0
      if strategy == :incremental
        @tokens.delete_if { |line, _| line >= frontier } if @old_fingerprints
        start = @checkpoints.keys.select { |line| line <= from_line && line <= frontier }.max || 0
        restart = @checkpoints.fetch(start)
        shift_cache(@tokens, from_line, removed, inserted)
        shift_cache(@fingerprints, from_line, removed, inserted)
        shift_cache(@checkpoints, from_line, removed, inserted)
        @old_fingerprints = @fingerprints.dup
        @old_checkpoints = @checkpoints.dup
        @fingerprints.delete_if { |line, _| line > start }
        @checkpoints.delete_if { |line, _| line > start }
        @checkpoints[start] = restart
        @frontier = start
        @dirty_until = from_line + inserted
        @lexer = @checkpoints.fetch(start).restore
      else
        @tokens.clear
        @frontier = 0
      end
      @count = updated_count
      @source = @offsets = @driver = nil
      @structure&.edit(from_line: from_line, removed: removed, inserted: inserted)
      self
    end

    # frontier is the first line not yet proven current (an exclusive boundary).
    def advance(until_line:, from_line: nil)
      return self if @count.zero?
      validate_index(until_line)
      @last_scanned_lines = 0
      return self if until_line < frontier && @tokens.key?(until_line) &&
        (from_line.nil? || (from_line..until_line).all? { |line| @tokens.key?(line) })
      Timeout.timeout(@max_seconds) do
        if @count > @max_lines
          fallback!(:window, "document exceeds #{@max_lines} lines")
        end
        case strategy
        when :incremental then advance_incremental(until_line)
        when :full then advance_full
        when :window then advance_window(from_line || until_line, until_line)
        end
      end
      self
    rescue ResourceLimitError, UnsupportedLexerError => error
      raise if requested_strategy == :incremental && error.is_a?(UnsupportedLexerError)
      fallback!(:window, error.message)
      advance_window(from_line || until_line, until_line)
      self
    rescue Timeout::Error
      fallback!(:window, "lexing exceeded #{@max_seconds} seconds")
      ((from_line || until_line)..until_line).each { |index| @tokens[index] = plain(index) }
      @frontier = until_line + 1
      self
    end

    def checkpoint_bytes = checkpoints.values.sum(&:bytesize)

    private

    def initialize_lexer
      @lexer = fresh_lexer
      if strategy == :incremental
        raise UnsupportedLexerError, "#{@lexer.class.tag} has a custom stream driver" unless LexerDriver.supported?(@lexer)
        @checkpoints[0] = LexerStateSnapshot.new(@lexer, max_bytes: @max_checkpoint_bytes)
      end
    end

    def fresh_lexer
      lexer = LexerStateSnapshot.copy(@template)
      lexer.reset!
      lexer
    rescue UnsupportedLexerError
      @template.class.new(@template.options).tap(&:reset!)
    end

    def count
      value = @line_count.call
      raise ArgumentError, "line_count must return a nonnegative integer" unless value.is_a?(Integer) && value >= 0
      value
    end

    def validate_index(index)
      raise RangeError, "line outside document" unless index.is_a?(Integer) && index >= 0 && index < @count
    end

    def source_line(index)
      value = @lines.call(index)
      raise TypeError, "line provider must return a String" unless value.is_a?(String)
      encoding = value.encoding
      unless value.valid_encoding? && (encoding == Encoding::UTF_8 || encoding == Encoding::US_ASCII)
        raise EncodingError, "line provider must return valid UTF-8"
      end
      newline = value.index("\n")
      raise ArgumentError, "line provider returned multiple logical lines" if newline && newline != value.length - 1
      # Providers may omit separators, but an empty final line remains empty.
      index < @count - 1 && newline.nil? ? value + "\n" : value
    end

    def build_source
      return if @source
      parts = Array.new(@count)
      offsets = Array.new(@count + 1, 0)
      bytes = 0
      index = 0
      while index < @count
        line = source_line(index)
        line_bytes = line.bytesize
        raise ResourceLimitError, "line exceeds #{@max_line_bytes} bytes" if line_bytes > @max_line_bytes
        bytes += line_bytes
        raise ResourceLimitError, "document exceeds #{@max_bytes} bytes" if bytes > @max_bytes
        parts[index] = line
        offsets[index + 1] = bytes
        index += 1
      end
      @source, @offsets = parts.join.freeze, offsets.freeze
    end

    def advance_incremental(until_line)
      build_source
      @driver ||= LexerDriver.new(@lexer, @source, @offsets, start_line: frontier) do |line, tokens|
        @tokens[line] = tokens
      end
      before = @driver.scanned_lines
      @driver.advance(until_line: until_line) do |line, lexer|
        fingerprint = LexerStateSnapshot.fingerprint(lexer)
        previous = @old_fingerprints&.[](line)
        @fingerprints[line] = fingerprint
        @frontier = line
        if line >= @dirty_until && previous == fingerprint && @tokens.key?(line)
          # Only the declared edited interval changed. Equal state at an aligned
          # old boundary makes the untouched cached suffix reusable.
          @frontier += 1 while @tokens.key?(@frontier)
          @fingerprints.merge!(@old_fingerprints.select { |position, _| position >= line && position <= frontier })
          @checkpoints.merge!(@old_checkpoints.select { |position, _| position >= line && position <= frontier })
          @old_fingerprints = @old_checkpoints = nil
          frontier > until_line
        else
          checkpoint = @checkpoints.keys.select { |position| position < line }.max || 0
          if line - checkpoint >= @checkpoint_interval || line == @count || @checkpoints.key?(line)
            @checkpoints[line] = LexerStateSnapshot.new(lexer, max_bytes: @max_checkpoint_bytes)
          end
          false
        end
      end
      @last_scanned_lines = @driver.scanned_lines - before
      @frontier = [@frontier, @driver.line].max
      @old_fingerprints = @old_checkpoints = nil if frontier >= @count
    end

    def advance_full
      build_source
      @tokens = split_tokens(fresh_lexer.lex(@source), 0)
      @frontier = @count
      @last_scanned_lines = @count
    end

    def advance_window(first, last)
      Timeout.timeout(@max_seconds) { window_tokens(first, last) }
    rescue Timeout::Error
      @fallback_reason = "window lexing exceeded #{@max_seconds} seconds"
      (first..last).each { |index| @tokens[index] = plain(index) }
      @frontier = last + 1
    end

    def window_tokens(first, last)
      first = [first - @window_context, 0].max
      source = +""
      selected = []
      (first..last).each do |index|
        line = source_line(index)
        if line.bytesize > @max_line_bytes || source.bytesize + line.bytesize > @max_bytes
          @tokens[index] = plain(index)
        else
          selected << index
          source << line
        end
      end
      unless selected.empty?
        rows = split_tokens(fresh_lexer.lex(source), 0)
        selected.each_with_index { |index, offset| @tokens[index] = rows.fetch(offset, [].freeze) }
      end
      @frontier = last + 1
      @last_scanned_lines = selected.length
    end

    def split_tokens(tokens, first)
      result = {first => []}
      line = first
      tokens.each do |type, value|
        next if value.empty?
        unless value.include?("\n")
          row = result[line] ||= []
          row.last&.first == type ? row.last[1] << value : row << [type, value.dup]
          next
        end
        value.each_line do |part|
          row = result[line] ||= []
          row.last&.first == type ? row.last[1] << part : row << [type, part.dup]
          line += 1 if part.end_with?("\n")
        end
      end
      result.transform_values { |row| row.each { |pair| pair.last.freeze; pair.freeze }.freeze }
    end

    def plain(index)
      value = source_line(index)
      value.empty? ? [].freeze : [[Rouge::Token::Tokens::Text, value.dup.freeze].freeze].freeze
    end

    def fallback!(strategy, reason)
      @strategy, @fallback_reason = strategy, reason
      @driver = @source = @offsets = nil
      @tokens.clear
      @checkpoints.clear
      @fingerprints.clear
      @old_fingerprints = @old_checkpoints = nil
      @frontier = 0
    end

    def shift_cache(cache, first, removed, inserted)
      delta = inserted - removed
      shifted = {}
      cache.each do |line, value|
        if line < first
          shifted[line] = value
        elsif line >= first + removed
          shifted[line + delta] = value
        end
      end
      cache.replace(shifted)
    end

    def stabilize_structure(from_line)
      return 0 if @count.zero?
      advance(until_line: @count - 1, from_line: from_line)
      strategy == :incremental && @driver ? [@driver.line, @count].min : @count
    end
  end
end
