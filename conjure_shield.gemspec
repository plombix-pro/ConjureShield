require_relative "lib/conjure_shield/version"

Gem::Specification.new do |spec|
  spec.name          = "conjure_shield"
  spec.version       = ConjureShield::VERSION
  spec.authors       = ["Stéphane Ballet"]
  spec.email         = ["plombix@gmail.com"]
  spec.summary       = "Rails test suggestion and implementation generator"
  spec.description   = "Rails gem that integrates via generators to analyze codebases and generate comprehensive test implementations using Prism, RuboCop, and RSpec"
  spec.homepage      = "https://github.com/plombix-pro/ConjureShield"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/plombix-pro/ConjureShield"
  spec.metadata["bug_tracker_uri"] = "https://github.com/plombix-pro/ConjureShield/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*"]
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", ">= 7.0.0"
  spec.add_dependency "prism", ">= 0.29.0"
  spec.add_dependency "rubocop", ">= 1.50.0"
  spec.add_dependency "rubocop-rails", ">= 2.20.0"
  spec.add_dependency "rubocop-rspec", ">= 2.24.0"
end