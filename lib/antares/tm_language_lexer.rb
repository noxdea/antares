# frozen_string_literal: true

require "timeout"

module Antares
  class TMLanguageLexer < Rouge::Lexer
    MAX_SOURCE_BYTES = 8 * 1024 * 1024
    MAX_SECONDS = 0.2
    MAX_INCLUDE_DEPTH = 64
    MAX_CONTEXT_DEPTH = 256
    MAX_NULL_STEPS = 32
    Context = Struct.new(:patterns, :ending, :token, :delimiter_token, :end_captures,
      :apply_end_last, keyword_init: true)

    class << self
      attr_reader :definition

      def build(definition)
        Class.new(self).tap do |lexer|
          lexer.instance_variable_set(:@definition, definition)
          lexer.define_singleton_method(:tag) { definition.tag }
        end.new
      end
    end

    def initialize(options = {})
      super
      @max_source_bytes = Integer(self.options.fetch("max_bytes", MAX_SOURCE_BYTES))
      @max_seconds = Float(self.options.fetch("max_seconds", MAX_SECONDS))
      raise ArgumentError, "max_bytes must be positive" unless @max_source_bytes.positive?
      raise ArgumentError, "max_seconds must be positive and finite" unless @max_seconds.positive? && @max_seconds.finite?
    rescue ArgumentError, TypeError
      raise ArgumentError, "invalid tmLanguage lexer limits"
    end

    def reset!
      @expanded = {}
    end

    def stream_tokens(source, &emit)
      raise ResourceLimitError, "source exceeds #{@max_source_bytes} bytes" if source.bytesize > @max_source_bytes

      Timeout.timeout(@max_seconds, ResourceLimitError) { tokenize(source, &emit) }
    end

    private

    def tokenize(source, &emit)
      definition = self.class.definition
      contexts = [Context.new(patterns: definition.patterns, token: Rouge::Token::Tokens::Text)]
      position = 0
      null_steps = 0
      while position < source.length
        context = contexts.last
        ending = context.ending&.match(source, position)
        rule, matching = next_rule(expanded(context.patterns), source, position)
        use_ending = ending && (!matching || ending.begin(0) < matching.begin(0) ||
          (ending.begin(0) == matching.begin(0) && !context.apply_end_last))
        boundary = use_ending ? ending&.begin(0) : matching&.begin(0)
        unless boundary
          emit.call(context.token, source[position..])
          break
        end
        if boundary > position
          emit.call(context.token, source[position...boundary])
          position = boundary
          null_steps = 0
          next
        end

        before = position
        if use_ending
          emit_match(source, ending, context.delimiter_token || context.token,
            context.end_captures || {}, &emit)
          position = ending.end(0)
          contexts.pop
        elsif rule.is_a?(Grammar::MatchRule)
          raise GrammarError, "match regex consumed no input" if matching.end(0) == position

          emit_match(source, matching, rule.token || context.token, rule.captures, &emit)
          position = matching.end(0)
        else
          emit_match(source, matching, rule.token || context.token, rule.begin_captures, &emit)
          position = matching.end(0)
          raise ResourceLimitError, "grammar context nesting exceeds #{MAX_CONTEXT_DEPTH}" if contexts.length >= MAX_CONTEXT_DEPTH

          contexts << Context.new(patterns: rule.patterns,
            ending: end_regexp(rule, matching),
            token: rule.content_token || rule.token || context.token,
            delimiter_token: rule.token || context.token,
            end_captures: rule.end_captures,
            apply_end_last: rule.apply_end_last)
        end
        null_steps = position == before ? null_steps + 1 : 0
        raise GrammarError, "grammar made too many zero-width transitions" if null_steps > MAX_NULL_STEPS
      end
    end

    def next_rule(patterns, source, position)
      selected_rule = selected_match = nil
      patterns.each do |rule|
        matching = rule.regexp.match(source, position)
        next unless matching
        next if selected_match && selected_match.begin(0) <= matching.begin(0)

        selected_rule = rule
        selected_match = matching
      end
      [selected_rule, selected_match]
    end

    def expanded(patterns)
      @expanded[patterns.object_id] ||= begin
        cycle = [false]
        count = [0]
        rules = expand_patterns(patterns, {patterns.object_id => true}, 0, cycle, count).freeze
        raise GrammarError, "recursive include contains no matching rules" if rules.empty? && cycle.first

        rules
      end
    end

    def expand_patterns(patterns, active, depth, cycle, count)
      raise ResourceLimitError, "grammar include nesting exceeds #{MAX_INCLUDE_DEPTH}" if depth >= MAX_INCLUDE_DEPTH

      patterns.flat_map { |rule| expand_rule(rule, active, depth, cycle, count) }
    end

    def expand_rule(rule, active, depth, cycle, count)
      raise ResourceLimitError, "grammar include nesting exceeds #{MAX_INCLUDE_DEPTH}" if depth >= MAX_INCLUDE_DEPTH

      if rule.is_a?(Grammar::MatchRule) || rule.is_a?(Grammar::BeginRule)
        count[0] += 1
        raise ResourceLimitError, "expanded grammar exceeds #{Grammar::MAX_RULES} rules" if count[0] > Grammar::MAX_RULES

        return [rule]
      end
      return expand_patterns(rule.patterns, active, depth + 1, cycle, count) if rule.is_a?(Grammar::GroupRule)

      target = if %w[$self $base].include?(rule.target)
        self.class.definition.patterns
      else
        self.class.definition.repository.fetch(rule.target.delete_prefix("#"))
      end
      target_patterns = target.is_a?(Array) ? target : (target.patterns if target.is_a?(Grammar::GroupRule))
      return expand_rule(target, active, depth + 1, cycle, count) unless target_patterns

      key = target_patterns.object_id
      if active[key]
        cycle[0] = true
        return []
      end
      expand_patterns(target_patterns, active.merge(key => true), depth + 1, cycle, count)
    rescue KeyError
      raise GrammarError, "unknown repository include #{rule.target.inspect}"
    end

    def end_regexp(rule, matching)
      return rule.ending unless rule.dynamic_end

      source = rule.end_source.gsub(/(?<!\\)\\([1-9])/) do
        index = Regexp.last_match(1).to_i
        capture = matching[index]
        raise GrammarError, "end capture #{index} did not participate in begin regex" unless capture

        Regexp.escape(capture)
      end
      raise ResourceLimitError, "expanded end regex exceeds #{Grammar::MAX_REGEX_BYTES} bytes" if source.bytesize > Grammar::MAX_REGEX_BYTES

      Regexp.new(source)
    rescue RegexpError, IndexError => error
      raise GrammarError, "invalid expanded end regex: #{error.message.byteslice(0, 256)}"
    end

    def emit_match(source, matching, base_token, captures)
      first = matching.begin(0)
      last = matching.end(0)
      ranges = captures.filter_map do |index, token|
        start = matching.begin(index)
        finish = matching.end(index)
        [start, finish, token, index] if start && finish && finish > start
      rescue IndexError
        raise GrammarError, "capture #{index} does not exist in regex"
      end
      boundaries = ([first, last] + ranges.flat_map { |range| range.first(2) }).uniq.sort
      boundaries.each_cons(2) do |start, finish|
        range = ranges.select { |candidate| candidate[0] <= start && finish <= candidate[1] }
          .min_by { |candidate| [candidate[1] - candidate[0], -candidate[3]] }
        yield(range ? range[2] : base_token, source[start...finish])
      end
    end
  end
end
