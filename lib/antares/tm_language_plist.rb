# frozen_string_literal: true

require "rexml/parsers/pullparser"
require "rexml/text"

module Antares
  class TMLanguagePlist
    ELEMENTS = %w[plist dict array key string integer real true false date data].freeze
    PLIST_DOCTYPE = %r{<!DOCTYPE\s+plist\s+PUBLIC\s+
      "-//Apple(?:\s+Computer)?//DTD\s+PLIST\s+1\.0//EN"\s+
      "http://www\.apple\.com/DTDs/PropertyList-1\.0\.dtd"\s*>}ix
    Frame = Struct.new(:name, :attributes, :text, :children, keyword_init: true)

    def self.parse(source, max_depth:)
      raise GrammarError, "tmLanguage XML entity declarations are unsupported" if source.match?(/<!ENTITY/i)
      declaration = source.match(PLIST_DOCTYPE)
      prefix = source[0...declaration.begin(0)] if declaration
      if prefix&.match?(/\A\s*(?:<\?xml\b.*?\?>\s*)?\z/m)
        source = prefix + source[declaration.end(0)..].to_s
      end
      raise GrammarError, "unsupported tmLanguage XML document type" if source.match?(/<!DOCTYPE/i)

      new(source, max_depth).parse
    rescue REXML::ParseException, ArgumentError, RangeError => error
      raise GrammarError, "invalid tmLanguage plist: #{error.message.byteslice(0, 256)}"
    end

    def initialize(source, max_depth)
      @parser = REXML::Parsers::PullParser.new(source)
      @max_depth = max_depth
      @frames = []
      @roots = []
    end

    def parse
      while @parser.has_next?
        event = @parser.pull
        case event.event_type
        when :start_element then start(event[0], event[1])
        when :end_element then finish(event[0])
        when :text then text(event[0], entities: true)
        when :cdata then text(event[0], entities: false)
        end
      end
      raise GrammarError, "plist must contain one plist root" unless @frames.empty? && @roots.length == 1 && @roots.first.first == "plist"

      @roots.first.last
    end

    private

    def start(name, attributes)
      raise GrammarError, "unsupported plist element #{name.inspect}" unless ELEMENTS.include?(name)
      raise ResourceLimitError, "tmLanguage nesting exceeds #{@max_depth}" if @frames.length >= @max_depth
      allowed_attributes = name == "plist" && (attributes.keys - ["version"]).empty?
      raise GrammarError, "unsupported attributes on plist element #{name.inspect}" unless attributes.empty? || allowed_attributes

      @frames << Frame.new(name: name, attributes: attributes, text: +"", children: [])
    end

    def text(value, entities:)
      value = decode_entities(value) if entities
      raise GrammarError, "text outside plist root" if @frames.empty? && !value.strip.empty?

      @frames.last&.text&.concat(value)
    end

    def finish(name)
      frame = @frames.pop
      raise GrammarError, "mismatched plist element" unless frame&.name == name

      value = decode(frame)
      if @frames.empty?
        @roots << [name, value]
      else
        @frames.last.children << [name, value]
      end
    end

    def decode(frame)
      scalar = !%w[plist dict array].include?(frame.name)
      raise GrammarError, "plist container contains text" if !scalar && !frame.text.strip.empty?
      raise GrammarError, "plist scalar contains child elements" if scalar && !frame.children.empty?

      case frame.name
      when "plist"
        raise GrammarError, "plist root must contain one value" unless frame.children.length == 1

        frame.children.first.last
      when "dict" then decode_dict(frame.children)
      when "array" then frame.children.map(&:last)
      when "key", "string", "date", "data" then scalar_text(frame)
      when "integer" then integer(scalar_text(frame))
      when "real" then real(scalar_text(frame))
      when "true" then boolean(frame, true)
      when "false" then boolean(frame, false)
      end
    end

    def scalar_text(frame)
      frame.text
    end

    def decode_entities(value)
      remainder = value.gsub(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/i, "")
      raise GrammarError, "unsupported plist entity" if remainder.include?("&")

      REXML::Text.unnormalize(value)
    end

    def decode_dict(children)
      raise GrammarError, "plist dict must alternate keys and values" unless children.length.even?

      result = {}
      children.each_slice(2) do |key, entry|
        raise GrammarError, "plist dict entry is missing a key" unless key.first == "key" && !key.last.empty?
        raise GrammarError, "plist dict entry is missing a value" if entry.first == "key"
        raise GrammarError, "duplicate plist key #{key.last.inspect}" if result.key?(key.last)

        result[key.last] = entry.last
      end
      result
    end

    def integer(value)
      raise GrammarError, "invalid plist integer" unless value.match?(/\A[+-]?\d{1,64}\z/)

      Integer(value, 10)
    end

    def boolean(frame, value)
      raise GrammarError, "plist boolean must be empty" unless frame.text.strip.empty?

      value
    end

    def real(value)
      number = Float(value)
      raise GrammarError, "invalid plist real" unless number.finite?

      number
    rescue ArgumentError
      raise GrammarError, "invalid plist real"
    end
  end
end
