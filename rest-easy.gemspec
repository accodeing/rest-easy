# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rest_easy/version"

Gem::Specification.new do |spec|
  spec.name          = "rest-easy"
  spec.authors       = ["Jonas Schubert Erlandsson","Claude Code"]
  spec.email         = ["jonas@accodeing.com"]
  spec.license       = "MIT"
  spec.version       = RestEasy::VERSION.dup

  spec.summary       = "Boilerplate for REST API libraries, using on dry-rb"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/accodeing/rest-easy"
  spec.files         = Dir["CHANGELOG.md", "LICENSE", "README.md", "dry-validation.gemspec", "lib/**/*", "config/*.yml"]
  spec.bindir        = "bin"
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.1.0"

  spec.add_runtime_dependency "dry-types", "~> 1.2"

  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "dry-configurable", "~> 0.14"
  spec.add_dependency "faraday", "~> 2.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
