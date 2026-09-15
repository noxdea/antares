# frozen_string_literal: true

require_relative "antares/version"
require "rouge"

module Antares
  class Error < StandardError; end
  class UnsupportedLexerError < Error; end
  class ResourceLimitError < Error; end
  class GrammarError < Error; end

  def self.compatible?(lexer)
    klass = lexer.is_a?(Class) ? lexer : lexer.class
    return :window unless Rouge.version == COMPATIBILITY_VERSION
    COMPATIBILITY.fetch(klass.tag, :window)
  end
end

require_relative "antares/compatibility"
require_relative "antares/lexer_state_snapshot"
require_relative "antares/lexer_driver"
require_relative "antares/highlighter"
require_relative "antares/structure"
require_relative "antares/grammar"

module Antares
  private_constant :TMLanguageLexer, :TMLanguagePlist
end
