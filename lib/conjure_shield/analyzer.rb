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

    def extract_model_info(file, ast)
      model_name = File.basename(file, ".rb").capitalize
      return unless model_name

      @ast_nodes << { file: file, model: model_name, type: :model }
    end

    def extract_controller_info(file, ast)
      controller_name = File.basename(file, ".rb").capitalize
      return unless controller_name

      @ast_nodes << { file: file, controller: controller_name, type: :controller }
    end

    def extract_serializer_info(file, ast)
      serializer_name = File.basename(file, ".rb").capitalize
      return unless serializer_name

      @ast_nodes << { file: file, serializer: serializer_name, type: :serializer }
    end

    def extract_helper_methods(file, ast)
      return unless File.basename(file).include?("_helper")

      @ast_nodes << { file: file, type: :helper }
    end

    def extract_callbacks(file, ast)
      callbacks = []
      ast.each_node(:send) do |node|
        callback_methods = [:before_save, :after_save, :before_create, :after_create,
                           :before_update, :after_update, :before_destroy, :after_destroy,
                           :before_validation, :after_validation, :around_save, :around_create]
        if callback_methods.include?(node.method_name)
          callbacks << node.method_name
        end
      end
      return if callbacks.empty?

      @ast_nodes << { file: file, callbacks: callbacks, type: :callbacks }
    end

    def extract_scopes(file, ast)
      scopes = []
      ast.each_node(:send) do |node|
        if node.method_name == :scope && node.arguments.any?
          scopes << node.arguments[0].children[0] if node.arguments[0].is_a?(Prism::Nodes::String)
        end
      end
      return if scopes.empty?

      @ast_nodes << { file: file, scopes: scopes, type: :scopes }
    end

    def extract_validations(file, ast)
      validations = []
      ast.each_node(:send) do |node|
        if node.method_name == :validates
          node.arguments.each do |arg|
            if arg.is_a?(Prism::Nodes::Array)
              arg.children.each do |child|
                if child.is_a?(Prism::Nodes::Symbol)
                  validations << child.children[0]
                elsif child.is_a?(Prism::Nodes::String)
                  validations << child.children[0]
                end
              end
            end
          end
        end
      end
      return if validations.empty?

      @ast_nodes << { file: file, validations: validations, type: :validations }
    end

    def extract_associations(file, ast)
      associations = []
      ast.each_node(:send) do |node|
        assoc_methods = [:belongs_to, :has_many, :has_one, :has_and_belongs_to_many,
                        :has_many_through, :has_one_through]
        if assoc_methods.include?(node.method_name)
          associations << node.method_name
        end
      end
      return if associations.empty?

      @ast_nodes << { file: file, associations: associations, type: :associations }
    end

    def extract_custom_methods(file, ast)
      methods = []
      ast.each_node(:def) do |node|
        next if [:initialize, :to_json, :to_yaml, :inspect, :class, :new, :attr_accessor,
                :attr_reader, :attr_writer, :attr, :attr_readonly].include?(node.method_name)
        methods << node.method_name
      end
      return if methods.empty?

      @ast_nodes << { file: file, methods: methods, type: :custom_methods }
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
      delegations = []
      ast.each_node(:send) do |node|
        if node.method_name == :delegate
          delegations << node.method_name
        end
      end
      return if delegations.empty?

      @ast_nodes << { file: file, delegations: delegations, type: :delegation }
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
      controller = @ast_nodes.find { |n| n[:type] == :controller }
      model = @ast_nodes.find { |n| n[:type] == :model }

      return unless controller && model

      @missing_tests << {
        type: :integration,
        controller: controller[:controller],
        model: model[:model],
        suggestions: [
          { name: "user workflow: create and view", type: :create_view },
          { name: "user workflow: edit and update", type: :edit_update },
          { name: "user workflow: delete", type: :delete },
          { name: "view details", type: :view_details }
        ]
      }

      @missing_tests << {
        type: :api,
        controller: controller[:controller],
        model: model[:model],
        suggestions: [
          { name: "GET list", type: :get_list },
          { name: "GET single", type: :get_single },
          { name: "POST create", type: :post_create },
          { name: "PUT update", type: :put_update },
          { name: "DELETE destroy", type: :delete_destroy }
        ]
      }

      @missing_tests << {
        type: :feature,
        controller: controller[:controller],
        model: model[:model],
        suggestions: [
          { name: "user story: create and view", type: :create_view_feature },
          { name: "user story: edit", type: :edit_feature },
          { name: "user story: delete", type: :delete_feature },
          { name: "user story: view details", type: :view_details_feature }
        ]
      }
    end
  end
end
