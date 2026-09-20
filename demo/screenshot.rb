# frozen_string_literal: true

require "fileutils"
require "antares"
require_relative "png_helper"

source = ["class Demo", "  def highlight(value)", "    value.to_s", "  end", "end", ""].map { |line| "#{line}\n" }
highlighter = Antares::Highlighter.new(
  lexer: Rouge::Lexers::Ruby.new,
  lines: ->(index) { source.fetch(index) },
  line_count: -> { source.length }
)
tokens = highlighter.tokens_in(0...(source.length))
width = 1_000
height = source.length * 64 + 48
rgba = [19, 24, 32, 255] * width * height
tokens.each_with_index do |line, row|
  x = 42
  line.each do |token, text|
    color = case token.to_s
    when /Keyword/ then [255, 121, 198, 255]
    when /Name/ then [128, 203, 196, 255]
    when /Literal|Number/ then [255, 203, 107, 255]
    when /Comment/ then [118, 133, 153, 255]
    else [155, 170, 189, 255]
    end
    width_px = [text.delete("\n").length * 12, 6].max
    index = (row * 64 + 22) * width * 4 + x * 4
    width_px.times do |column|
      12.times { |offset| rgba[index + column * 4 + offset * width * 4, 4] = color }
    end
    x += width_px + 8
  end
end
FileUtils.mkdir_p("docs/media")
DemoPNG.write("docs/media/screenshot.png", width, height, rgba.pack("C*"))
