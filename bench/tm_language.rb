# frozen_string_literal: true

require "benchmark"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "antares"

path = File.expand_path("../test/fixtures/grammar/mini.tmLanguage.json", __dir__)
load_time = Benchmark.realtime { Antares::Grammar.load_tmlanguage(path) }
template = Antares::Grammar.load_tmlanguage(path)
source = Array.new(500) { |index| "def value_#{index}(arg) # comment\n" }.join
samples = Array.new(20) do
  Benchmark.realtime { template.class.new(max_seconds: 2).lex(source).to_a }
end
median = samples.sort.fetch(samples.length / 2)

puts "tmLanguage, 500 lines: load=#{(load_time * 1000).round(3)} ms, lex median=#{(median * 1000).round(3)} ms"
if ENV["BUDGET"] == "1"
  raise "tmLanguage load exceeded 50 ms" unless load_time < 0.05
  raise "tmLanguage lex exceeded 100 ms" unless median < 0.1
end
