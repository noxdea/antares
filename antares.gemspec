# frozen_string_literal: true

require_relative "lib/antares/version"

Gem::Specification.new do |spec|
  spec.name = "antares"
  spec.version = Antares::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Incremental highlighting for Rouge lexers"
  spec.homepage = "https://github.com/noxdea/antares"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }
  spec.files = Dir.chdir(__dir__) { Dir["{lib,sig,exe,assets,vendor}/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"].select { |path| File.file?(path) } }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}).map { |path| File.basename(path) }
  spec.require_paths = ["lib"]
  spec.add_dependency "rouge", "~> 5.0"
  spec.add_dependency "rexml", ">= 3.2", "< 4"
end
