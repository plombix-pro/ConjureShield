require "conjure_shield/version"
require "conjure_shield/railtie"
require "conjure_shield/analyzer"
require "conjure_shield/test_generator"
require "conjure_shield/templates"

module Conjureshield
  class << self
    def analyze(path)
      Conjureshield::Analyzer.new(path).analyze
    end

    def generate_tests(code, suggestions)
      TestGenerator.generate(code, suggestions)
    end

    def generate_integration_tests(controller, model)
      TestGenerator.new(nil, nil).send(:generate_integration_test, {controller: controller, model: model}, nil)
    end

    def generate_api_tests(controller, model)
      TestGenerator.new(nil, nil).send(:generate_api_integration_test, {controller: controller, model: model}, nil)
    end

    def generate_feature_tests(controller, model)
      TestGenerator.new(nil, nil).send(:generate_feature_integration_test, {controller: controller, model: model}, nil)
    end
  end
end
