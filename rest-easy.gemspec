# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rest_easy/version"

Gem::Specification.new do |spec|
  spec.name          = "rest-easy"
  spec.authors       = ["Jonas Schubert Erlandsson"]
  spec.email         = ["jonas@accodeing.com"]
  spec.license       = "MIT"
  spec.version       = RestEasy::VERSION.dup

  spec.summary       = "Boilerplate for REST API libraries, based on dry-rb"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/accodeing/rest-easy"
  spec.files         = Dir["CHANGELOG.md", "LICENSE", "README.md", "dry-validation.gemspec", "lib/**/*", "config/*.yml"]
  spec.bindir        = "bin"
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_runtime_dependency "dry-system", "~> 0.21"
  spec.add_runtime_dependency "dry-types", "~> 1.2"
  spec.add_runtime_dependency "dry-struct", "~> 1.4"

  spec.add_dependency "zeitwerk", "~> 2.5.4"
  spec.add_dependency "dry-container", "~> 0.9.0"
  spec.add_dependency "dry-auto_inject", "~> 0.9.0"
  spec.add_dependency "dry-inflector", "~> 0.2.1"
  spec.add_dependency "dry-configurable", "~> 0.14"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
