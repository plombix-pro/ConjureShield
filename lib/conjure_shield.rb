require "conjure_shield/version"
require "conjure_shield/railtie"
require "conjure_shield/analyzer"
require "conjure_shield/test_generator"

module ConjureShield
  class << self
    attr_accessor :install_shown

    def analyze(path)
      ConjureShield::Analyzer.new(path).analyze
    end

    def generate_tests(code, suggestions)
      TestGenerator.generate(code, suggestions)
    end

    def generate_integration_tests(controller, model)
      TestGenerator.new(nil, nil).send(:generate_integration_test, {controller: controller, model: model})
    end

    def generate_api_tests(controller, model)
      TestGenerator.new(nil, nil).send(:generate_api_test, {controller: controller, model: model})
    end

    def generate_feature_tests(controller, model)
      TestGenerator.new(nil, nil).send(:generate_feature_test, {controller: controller, model: model})
    end
  end
end
