# frozen_string_literal: true

require "benchmark"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "antares"

lines = Array.new(10_000) { |index| "value_#{index} = #{index}\n" }
highlighter = Antares::Highlighter.new(
  lexer: Rouge::Lexers::Python.new,
  lines: ->(index) { lines[index] },
  line_count: -> { lines.length },
  strategy: :incremental,
  checkpoint_interval: 64,
  max_seconds: 5
)
highlighter.tokens_in(0...lines.length)
structure = highlighter.structure
full = Benchmark.realtime { structure.fold_regions }
10.times do |iteration|
  lines[5000] = "value_5000 = (warmup_#{iteration})\n"
  highlighter.edit(from_line: 5000, removed: 1, inserted: 1)
  structure.fold_regions
end
samples = Array.new(30) do |iteration|
  Benchmark.realtime do
    lines[5000] = "value_5000 = (#{iteration})\n"
    highlighter.edit(from_line: 5000, removed: 1, inserted: 1)
    structure.fold_regions
  end
end
partial = samples.sort.fetch(samples.length / 2)

puts "structure, 10000 lines: full=#{(full * 1000).round(3)} ms, partial median=#{(partial * 1000).round(3)} ms"
if ENV["BUDGET"] == "1"
  raise "structure build exceeded 100 ms" unless full < 0.1
  raise "structure update exceeded 5 ms" unless partial < 0.005
end
