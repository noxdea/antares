# frozen_string_literal: true

require "rake/testtask"
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |test|
  test.libs << "lib" << "test"
  test.pattern = "test/**/*_test.rb"
end

desc "Measure performance (BUDGET=1 enables assertions)"
task :bench do
  # Keep cold-start compilation out of the visible-range latency, then use
  # YJIT for the repeated full-document structure workload.
  ruby "bench/highlighting.rb"
  ruby "--yjit", "bench/structure.rb"
end

task default: :test

desc "Regenerate the compatibility matrix against the installed Rouge"
task :compatibility do
  ruby "script/compatibility", "--write"
end
