# frozen_string_literal: true

require "zlib"

module DemoPNG
  module_function

  def write(path, width, height, rgba)
    scanlines = height.times.map { |row| "\0".b + rgba.byteslice(row * width * 4, width * 4) }.join
    chunk = ->(kind, data) { [data.bytesize].pack("N") + kind + data + [Zlib.crc32(kind + data)].pack("N") }
    png = "\x89PNG\r\n\x1a\n".b
    png << chunk.call("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNC5"))
    png << chunk.call("IDAT", Zlib::Deflate.deflate(scanlines, 9))
    png << chunk.call("IEND", "".b)
    File.binwrite(path, png)
  end
end
