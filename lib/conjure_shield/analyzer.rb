require "parser/current"
require "prism"
require "rubocop"
require "rubocop-rails"
require "rubocop-rspec"
require "json"
require "net/http"
require "uri"
require "nokogiri"

module Conjureshield
  class Analyzer
    attr_reader :codebase_path, :files, :ast_nodes, :missing_tests, :existing_tests

    def initialize(path)
      @codebase_path = File.expand_path(path)
      @ast_nodes = []
      @missing_tests = []
      @existing_tests = []
      @files = []
    end

    def analyze
      scan_ruby_files
      scan_existing_tests
      analyze_ast
      detect_missing_tests
      self
    end

    private

    def scan_ruby_files
      Dir.glob("#{codebase_path}/**/*.rb").each do |file|
        next if file.include?("/vendor/") || file.include?("/node_modules/")
        next if file.include?("/test/") || file.include?("/spec/")
        next if file.include?("/db/") || file.include?("/config/")

        content = File.read(file)
        @files << { path: file, content: content }
        parse_file(file, content)
      end
    end

    def parse_file(file, content)
      begin
        ast = Prism.parse(content).value
        @ast_nodes << { file: file, ast: ast, content: content }
        extract_model_info(file, ast)
        extract_controller_info(file, ast)
        extract_serializer_info(file, ast)
        extract_helper_methods(file, ast)
        extract_callbacks(file, ast)
        extract_scopes(file, ast)
        extract_validations(file, ast)
        extract_associations(file, ast)
        extract_custom_methods(file, ast)
        extract_factories(file, content)
        extract_serialization(file, content)
        extract_delegation(file, ast)
        extract_stimulus(file, content)
        extract_cable_subscriptions(file, content)
        extract_cable_broadcasts(file, content)
        extract_describe_blocks(file, content)
      rescue Prism::ParseError => e
        warn "Parse error in #{file}: #{e.message}"
      end
    end

    def scan_existing_tests
      # Look for both RSpec and Minitest structures safely
      Dir.glob("#{codebase_path}/{spec,test}/**/*_{spec,test}.rb").each do |file|
        next if file.include?("/vendor/") || file.include?("/node_modules/")

        @existing_tests << {
          file: file,
          filename: File.basename(file)
        }
      end
    end

    def analyze_ast
      # Gather all granular metadata fragments found by your visitors
      metadata_nodes = @ast_nodes.select do |n| 
        [:callbacks, :validations, :scopes, :associations, :custom_methods, :delegation].include?(n[:type]) 
      end
      
      # Find the primary component definitions
      primary_components = @ast_nodes.select { |n| [:model, :controller, :serializer, :helper].include?(n[:type]) }

      # Cross-reference and enrich the primary components with their specific features
      # This keeps @ast_nodes flat so your CLI counters still work!
      primary_components.each do |component|
        component[:metadata] ||= {}
        
        file_metadata = metadata_nodes.select { |meta| meta[:file] == component[:file] }
        file_metadata.each do |meta|
          payload_key = meta[:type]
          component[:metadata][payload_key] = meta[payload_key] || meta[:methods] || meta[:delegations]
        end
      end
    end

    def extract_model_info(file, ast)
      return unless file.include?("/app/models/")
      
      model_name = File.basename(file, ".rb").split('_').map(&:capitalize).join
      @ast_nodes << { file: file, model: model_name, type: :model }
    end

    def extract_controller_info(file, ast)
      return unless file.include?("/app/controllers/")
      
      controller_name = File.basename(file, ".rb").split('_').map(&:capitalize).join
      @ast_nodes << { file: file, controller: controller_name, type: :controller }
    end

    def extract_serializer_info(file, ast)
      return unless file.include?("/app/serializers/")
      
      serializer_name = File.basename(file, ".rb").split('_').map(&:capitalize).join
      @ast_nodes << { file: file, serializer: serializer_name, type: :serializer }
    end

    def extract_helper_methods(file, ast)
      return unless File.basename(file).include?("_helper")

      @ast_nodes << { file: file, type: :helper }
    end

    def extract_callbacks(file, ast)
      visitor = Class.new(Prism::Visitor) do
        attr_reader :callbacks

        def initialize
          @callbacks = []
          @targets = [:before_save, :after_save, :before_create, :after_create,
                      :before_update, :after_update, :before_destroy, :after_destroy,
                      :before_validation, :after_validation, :around_save, :around_create]
        end

        def visit_call_node(node)
          @callbacks << node.name if @targets.include?(node.name)
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.callbacks.empty?

      @ast_nodes << { file: file, callbacks: visitor.callbacks, type: :callbacks }
    end

    def extract_scopes(file, ast)
      visitor = Class.new(Prism::Visitor) do
        attr_reader :scopes

        def initialize
          @scopes = []
        end

        def visit_call_node(node)
          if node.name == :scope && node.arguments&.arguments&.any?
            arg = node.arguments.arguments.first
            if arg.is_a?(Prism::StringNode)
              @scopes << arg.content
            elsif arg.is_a?(Prism::SymbolNode)
              @scopes << arg.value
            end
          end
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.scopes.empty?

      @ast_nodes << { file: file, scopes: visitor.scopes, type: :scopes }
    end

    def extract_validations(file, ast)
      visitor = Class.new(Prism::Visitor) do
        attr_reader :validations

        def initialize
          @validations = []
        end

        def visit_call_node(node)
          if node.name == :validates && node.arguments&.arguments&.any?
            node.arguments.arguments.each do |arg|
              if arg.is_a?(Prism::SymbolNode)
                @validations << arg.value
              elsif arg.is_a?(Prism::StringNode)
                @validations << arg.content
              end
            end
          end
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.validations.empty?

      @ast_nodes << { file: file, validations: visitor.validations, type: :validations }
    end

    def extract_associations(file, ast)
      visitor = Class.new(Prism::Visitor) do
        attr_reader :associations

        def initialize
          @associations = []
          @targets = [:belongs_to, :has_many, :has_one, :has_and_belongs_to_many,
                      :has_many_through, :has_one_through]
        end

        def visit_call_node(node)
          @associations << node.name if @targets.include?(node.name)
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.associations.empty?

      @ast_nodes << { file: file, associations: visitor.associations, type: :associations }
    end

    def extract_custom_methods(file, ast)
      visitor = Class.new(Prism::Visitor) do
        attr_reader :methods

        def initialize
          @methods = []
          @ignored = [:initialize, :to_json, :to_yaml, :inspect, :class, :new, :attr_accessor,
                      :attr_reader, :attr_writer, :attr, :attr_readonly]
        end

        def visit_def_node(node)
          @methods << node.name unless @ignored.include?(node.name)
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.methods.empty?

      @ast_nodes << { file: file, methods: visitor.methods, type: :custom_methods }
    end

    def extract_factories(file, content)
      return unless file.include?("factories") || file.include?("factory")

      @ast_nodes << { file: file, type: :factory }
    end

    def extract_serialization(file, content)
      return unless content.include?("to_json") || content.include?("to_yaml")

      @ast_nodes << { file: file, type: :serialization }
    end

    def extract_delegation(file, ast)
      visitor = Class.new(Prism::Visitor) do
        attr_reader :delegations

        def initialize
          @delegations = []
        end

        def visit_call_node(node)
          @delegations << node.name if node.name == :delegate
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.delegations.empty?

      @ast_nodes << { file: file, delegations: visitor.delegations, type: :delegation }
    end

    def extract_stimulus(file, content)
      return unless file.include?("application.js") || file.include?("stimulus")

      @ast_nodes << { file: file, type: :stimulus }
    end

    def extract_cable_subscriptions(file, content)
      subscriptions = []
      content.scan(/subscribe\s*\(\s*["'](?<sub>[^"]+)["']\s*,\s*["'](?<channel>[^"]+)["']/).each do |match|
        subscriptions << { subscription: match[:sub], channel: match[:channel] }
      end
      return if subscriptions.empty?

      @ast_nodes << { file: file, subscriptions: subscriptions, type: :cable_subscription }
    end

    def extract_cable_broadcasts(file, content)
      channels = []
      content.scan(/broadcast_to\s*\(\s*["'](?<channel>[^"]+)["']/).each do |match|
        channels << match[:channel]
      end
      return if channels.empty?

      @ast_nodes << { file: file, channels: channels, type: :cable_broadcast }
    end

    def extract_describe_blocks(file, content)
      blocks = []
      content.scan(/RSpec\.describe\s+\["?([^"\]]+)"/).each do |match|
        blocks << { name: match[0], suggestions: [] }
      end
      blocks
    end

    def detect_missing_tests
      models = @ast_nodes.select { |n| n[:type] == :model }
      controllers = @ast_nodes.select { |n| n[:type] == :controller }

      # 1. Evaluate missing Model tests
      models.each do |model_node|
        expected_spec = "#{File.basename(model_node[:file], '.rb')}_spec.rb"
        has_test = @existing_tests.any? { |t| t[:filename] == expected_spec }

        unless has_test
          # Formatted as Hashes so suggestion[:name] works in your CLI
          suggestions = [
            { name: "Verify model initialization structure", type: :init }
          ]
          
          if model_node.dig(:metadata, :validations)&.any?
            suggestions << { name: "Test active validations", type: :validations }
          end
          
          if model_node.dig(:metadata, :associations)&.any?
            suggestions << { name: "Test active associations", type: :associations }
          end

          @missing_tests << {
            type: :unit,
            model: model_node[:model],
            file: model_node[:file],
            suggestions: suggestions
          }
        end
      end

      # 2. Evaluate missing Controller tests
      controllers.each do |controller_node|
        expected_spec = "#{File.basename(controller_node[:file], '.rb')}_spec.rb"
        has_test = @existing_tests.any? { |t| t[:filename] == expected_spec }

        unless has_test
          @missing_tests << {
            type: :request,
            controller: controller_node[:controller],
            file: controller_node[:file],
            suggestions: [
              { name: "Test standard GET #index response parameters", type: :get_index },
              { name: "Test POST #create branch handling", type: :post_create }
            ]
          }
        end
      end
    end
  end
end