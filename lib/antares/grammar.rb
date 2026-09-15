# frozen_string_literal: true

require "json"
require_relative "tm_language_plist"
require_relative "tm_language_lexer"

module Antares
  module Grammar
    MAX_BYTES = 2 * 1024 * 1024
    MAX_DEPTH = 64
    MAX_RULES = 10_000
    MAX_REGEX_BYTES = 16_384
    TOP_KEYS = %w[$schema name scopeName fileTypes firstLineMatch foldingStartMarker
      foldingStopMarker patterns repository uuid version comment
      information_for_contributors hideFromUser].freeze
    RULE_KEYS = %w[include match captures name begin end beginCaptures endCaptures
      contentName patterns applyEndPatternLast comment].freeze
    UNSUPPORTED_RULE_KEYS = %w[while whileCaptures repository disabled].freeze

    MatchRule = Struct.new(:regexp, :token, :captures, keyword_init: true)
    BeginRule = Struct.new(:regexp, :end_source, :ending, :dynamic_end, :token,
      :content_token, :begin_captures, :end_captures, :patterns, :apply_end_last,
      keyword_init: true)
    IncludeRule = Struct.new(:target, keyword_init: true)
    GroupRule = Struct.new(:patterns, keyword_init: true)
    Definition = Struct.new(:scope_name, :tag, :patterns, :repository, keyword_init: true)

    class UniqueHash < Hash
      def []=(key, value)
        raise GrammarError, "duplicate JSON object key #{key.inspect}" if key?(key)

        super
      end
    end
    private_constant :UniqueHash

    module_function

    def load_tmlanguage(path)
      raise ArgumentError, "path must be a String" unless path.is_a?(String) && !path.include?("\0")

      source = File.open(path, "rb") do |file|
        raise GrammarError, "tmLanguage must be a regular file" unless file.stat.file?
        raise ResourceLimitError, "tmLanguage exceeds #{MAX_BYTES} bytes" if file.stat.size > MAX_BYTES

        file.read(MAX_BYTES + 1) || "".b
      end
      raise ResourceLimitError, "tmLanguage exceeds #{MAX_BYTES} bytes" if source.bytesize > MAX_BYTES
      source = source.delete_prefix("\xEF\xBB\xBF".b).force_encoding(Encoding::UTF_8)
      raise GrammarError, "tmLanguage must be valid UTF-8" unless source.valid_encoding?

      value = parse(source)
      definition = Compiler.new.compile(value)
      TMLanguageLexer.build(definition)
    rescue SystemCallError => error
      raise GrammarError, "cannot read tmLanguage: #{error.message}"
    end

    def parse(source)
      case source.lstrip.getbyte(0)
      when 123
        JSON.parse(source, max_nesting: MAX_DEPTH, object_class: UniqueHash,
          allow_duplicate_key: false)
      when 60
        TMLanguagePlist.parse(source, max_depth: MAX_DEPTH)
      else
        raise GrammarError, "tmLanguage must be JSON or XML plist"
      end
    rescue JSON::ParserError => error
      raise GrammarError, "invalid tmLanguage JSON: #{error.message.byteslice(0, 256)}"
    end

    def token_for_scope(scope)
      return Rouge::Token::Tokens::Text unless scope.is_a?(String)

      name = scope.split.first.to_s.downcase
      case name
      when /\Ainvalid(?:\.|\z)/ then Rouge::Token::Tokens::Error
      when /\Acomment(?:\.|\z)/ then Rouge::Token::Tokens::Comment
      when /\A(?:string\.)?(?:regexp|regex)(?:\.|\z)/ then Rouge::Token::Tokens::Literal::String::Regex
      when /\Aconstant\.character\.escape(?:\.|\z)/ then Rouge::Token::Tokens::Literal::String::Escape
      when /\Astring(?:\.|\z)/ then Rouge::Token::Tokens::Literal::String
      when /\Aconstant\.numeric(?:\.|\z)/ then Rouge::Token::Tokens::Literal::Number
      when /\Aconstant\.language(?:\.|\z)/ then Rouge::Token::Tokens::Keyword::Constant
      when /\Akeyword(?:\.|\z)/ then Rouge::Token::Tokens::Keyword
      when /\Astorage\.type(?:\.|\z)/ then Rouge::Token::Tokens::Keyword::Type
      when /\Astorage(?:\.|\z)/ then Rouge::Token::Tokens::Keyword::Declaration
      when /\Aentity\.name\.function(?:\.|\z)/ then Rouge::Token::Tokens::Name::Function
      when /\A(?:entity\.name\.(?:class|type)|support\.class)(?:\.|\z)/ then Rouge::Token::Tokens::Name::Class
      when /\Aentity\.other\.attribute-name(?:\.|\z)/ then Rouge::Token::Tokens::Name::Attribute
      when /\Asupport\.function(?:\.|\z)/ then Rouge::Token::Tokens::Name::Builtin
      when /\Avariable(?:\.|\z)/ then Rouge::Token::Tokens::Name::Variable
      when /\Apunctuation(?:\.|\z)/ then Rouge::Token::Tokens::Punctuation
      when /\Amarkup\.heading(?:\.|\z)/ then Rouge::Token::Tokens::Generic::Heading
      when /\Amarkup\.bold(?:\.|\z)/ then Rouge::Token::Tokens::Generic::Strong
      when /\Amarkup\.italic(?:\.|\z)/ then Rouge::Token::Tokens::Generic::Emph
      when /\A(?:constant|support\.constant)(?:\.|\z)/ then Rouge::Token::Tokens::Name::Constant
      when /\Aentity\.name(?:\.|\z)/ then Rouge::Token::Tokens::Name
      else Rouge::Token::Tokens::Text
      end
    end

    class Compiler
      def initialize
        @rule_count = 0
      end

      def compile(value)
        object(value, "tmLanguage root")
        unknown = value.keys - TOP_KEYS
        raise GrammarError, "unsupported tmLanguage key #{unknown.first.inspect}" unless unknown.empty?

        scope = string(value["scopeName"], "scopeName")
        patterns = compile_patterns(value.fetch("patterns", []), 0)
        source_repository = value.fetch("repository", {})
        object(source_repository, "repository")
        repository = source_repository.to_h do |name, rule|
          raise GrammarError, "invalid repository name" unless name.is_a?(String) && !name.empty?

          [name.freeze, compile_rule(rule, 1)]
        end.freeze
        validate_includes(patterns, repository)
        repository.each_value { |rule| validate_includes([rule], repository) }
        tag = scope.split(".").last.to_s.gsub(/[^a-zA-Z0-9_+.-]/, "_")
        raise GrammarError, "scopeName does not contain a usable lexer tag" if tag.empty?

        Definition.new(scope_name: scope.freeze, tag: tag.downcase.freeze,
          patterns: patterns, repository: repository).freeze
      end

      private

      def compile_patterns(value, depth)
        raise GrammarError, "patterns must be an Array" unless value.is_a?(Array)
        raise ResourceLimitError, "tmLanguage nesting exceeds #{MAX_DEPTH}" if depth >= MAX_DEPTH

        value.map { |rule| compile_rule(rule, depth + 1) }.freeze
      end

      def compile_rule(value, depth)
        object(value, "grammar rule")
        unsupported = value.keys & UNSUPPORTED_RULE_KEYS
        raise GrammarError, "unsupported grammar rule key #{unsupported.first.inspect}" unless unsupported.empty?
        unknown = value.keys - RULE_KEYS
        raise GrammarError, "unsupported grammar rule key #{unknown.first.inspect}" unless unknown.empty?
        @rule_count += 1
        raise ResourceLimitError, "tmLanguage exceeds #{MAX_RULES} rules" if @rule_count > MAX_RULES

        kinds = %w[include match begin].select { |key| value.key?(key) }
        raise GrammarError, "grammar rule has incompatible operations" if kinds.length > 1

        case kinds.first
        when "include" then compile_include(value)
        when "match" then compile_match(value)
        when "begin" then compile_begin(value, depth)
        else
          raise GrammarError, "grammar rule must have one operation" unless value.key?("patterns")

          compile_group(value, depth)
        end
      end

      def compile_include(value)
        target = string(value["include"], "include")
        valid = %w[$self $base].include?(target) || target.match?(/\A#[^#\s]+\z/)
        raise GrammarError, "external grammar include #{target.inspect} is unsupported" unless valid
        raise GrammarError, "include rule has incompatible fields" unless (value.keys - %w[include comment]).empty?

        IncludeRule.new(target: target.freeze).freeze
      end

      def compile_match(value)
        allowed = %w[match captures name comment]
        raise GrammarError, "match rule has incompatible fields" unless (value.keys - allowed).empty?

        MatchRule.new(regexp: compile_regexp(value["match"]), token: optional_token(value["name"]),
          captures: compile_captures(value["captures"])).freeze
      end

      def compile_begin(value, depth)
        raise GrammarError, "begin rule requires end" unless value.key?("end")

        regexp = compile_regexp(value["begin"])
        ending = string(value["end"], "end")
        compiled_ending = validate_regexp(dynamic_source(ending), "end")
        shared = value["captures"]
        BeginRule.new(regexp: regexp, end_source: ending.freeze, ending: compiled_ending,
          dynamic_end: ending.match?(/(?<!\\)\\[1-9]/), token: optional_token(value["name"]),
          content_token: optional_token(value["contentName"]),
          begin_captures: compile_captures(value["beginCaptures"] || shared),
          end_captures: compile_captures(value["endCaptures"] || shared),
          patterns: compile_patterns(value.fetch("patterns", []), depth),
          apply_end_last: boolean(value.fetch("applyEndPatternLast", false), "applyEndPatternLast")).freeze
      end

      def compile_group(value, depth)
        raise GrammarError, "pattern group has incompatible fields" unless (value.keys - %w[patterns comment]).empty?

        GroupRule.new(patterns: compile_patterns(value["patterns"], depth)).freeze
      end

      def compile_captures(value)
        return {}.freeze if value.nil?
        object(value, "captures")

        value.to_h do |index, capture|
          raise GrammarError, "capture keys must be decimal indexes" unless index.is_a?(String) && index.match?(/\A\d{1,3}\z/)
          object(capture, "capture")
          unknown = capture.keys - %w[name comment]
          raise GrammarError, "unsupported capture key #{unknown.first.inspect}" unless unknown.empty?

          [Integer(index, 10), scope_token(string(capture["name"], "capture name"))]
        end.freeze
      end

      def compile_regexp(value)
        source = string(value, "match")
        validate_regexp(source, "match")
      end

      def validate_regexp(source, field)
        raise ResourceLimitError, "#{field} regex exceeds #{MAX_REGEX_BYTES} bytes" if source.bytesize > MAX_REGEX_BYTES

        Regexp.new(source)
      rescue RegexpError => error
        raise GrammarError, "invalid #{field} regex: #{error.message.byteslice(0, 256)}"
      end

      def dynamic_source(source)
        source.gsub(/(?<!\\)\\[1-9]/, "x")
      end

      def validate_includes(patterns, repository, seen = {})
        patterns.each do |rule|
          if rule.is_a?(IncludeRule) && rule.target.start_with?("#")
            name = rule.target.delete_prefix("#")
            raise GrammarError, "unknown repository include #{rule.target.inspect}" unless repository.key?(name)
          elsif rule.is_a?(BeginRule) || rule.is_a?(GroupRule)
            next if seen[rule.object_id]

            seen[rule.object_id] = true
            validate_includes(rule.patterns, repository, seen)
          end
        end
      end

      def optional_token(value)
        value.nil? ? nil : scope_token(string(value, "scope name"))
      end

      def scope_token(value)
        Grammar.__send__(:token_for_scope, value)
      end

      def object(value, name)
        raise GrammarError, "#{name} must be an object" unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
      end

      def string(value, name)
        raise GrammarError, "#{name} must be a nonempty String" unless value.is_a?(String) && !value.empty?

        value
      end

      def boolean(value, name)
        raise GrammarError, "#{name} must be true or false" unless value == true || value == false

        value
      end
    end
    private_constant :Compiler
    private_class_method :parse, :token_for_scope
  end
end
