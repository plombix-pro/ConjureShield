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
    RESTFUL_ACTIONS = %i[index show new create edit update destroy].freeze
    SINGULAR_ACTIONS = %i[show new create edit update destroy].freeze

    ACTION_ROUTE_MAP = {
      index: [:get_index, :index_pagination, :index_sorting],
      show: [:get_show, :show_with_associations],
      new: [:get_new, :new_form],
      create: [:post_create, :post_create_valid, :post_create_invalid, :post_create_redirect],
      edit: [:get_edit, :edit_form],
      update: [:put_patch_update_valid, :put_patch_update_invalid, :put_patch_update_redirect],
      destroy: [:delete_destroy, :delete_destroy_redirect]
    }.freeze

    attr_reader :codebase_path, :files, :ast_nodes, :missing_tests, :existing_tests, :routes, :routes_parsed

    def initialize(path)
      @codebase_path = File.expand_path(path)
      @ast_nodes = []
      @missing_tests = []
      @existing_tests = []
      @files = []
      @routes = {}
      @routes_parsed = false
    end

    def analyze
      scan_ruby_files
      scan_existing_tests
      analyze_ast
      parse_routes
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
            name = if arg.is_a?(Prism::StringNode)
                     arg.content
                   elsif arg.is_a?(Prism::SymbolNode)
                     arg.value
                   end
            @scopes << { name: name, args: [] } if name
          end
          super
        end
      end.new

      visitor.visit(ast)
      return if visitor.scopes.empty?

      @ast_nodes << { file: file, scopes: visitor.scopes, type: :scopes }
    end

    def extract_validations(file, ast)
      content = @files.find { |f| f[:path] == file }&.dig(:content) || ""
      validations = []

      content.each_line do |line|
        next unless line =~ /validates\s+(?::)?(\w[\w!?]*)/

        field = $1
        validators = []
        validators << :presence if line.include?("presence:")
        validators << :uniqueness if line.include?("uniqueness:")
        validators << :length if line.include?("length:")
        validators << :format if line.include?("format:")
        validators << :inclusion if line.include?("inclusion:")
        validators << :exclusion if line.include?("exclusion:")
        validators << :confirmation if line.include?("confirmation:")
        validators << :acceptance if line.include?("acceptance:")
        validators << :numericality if line.include?("numericality:")
        validators << :comparison if line.include?("comparison:")

        validations << { field: field, validators: validators }
      end

      return if validations.empty?

      @ast_nodes << { file: file, validations: validations, type: :validations }
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
          if @targets.include?(node.name)
            target = nil
            if node.arguments&.arguments&.first
              arg = node.arguments.arguments.first
              target = arg.value if arg.respond_to?(:value)
            end
            @associations << { type: node.name, target: target&.to_s&.classify }
          end
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

    def parse_routes
      routes_file = File.join(@codebase_path, "config", "routes.rb")
      return unless File.exist?(routes_file)

      @routes_parsed = true

      content = File.read(routes_file)
      prefix_stack = []
      block_stack = []

      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        if stripped =~ /\Aend\b/
          popped = block_stack.pop
          prefix_stack.pop if [:namespace, :scope_module].include?(popped)
          next
        end

        if stripped =~ /\bnamespace\s+(?::|["'])(\w+)\s+do\b/
          block_stack << :namespace
          prefix_stack << $1.camelize
          next
        end

        if stripped =~ /\bscope\s+module:\s*(?::|["'])(\w+)["']?\s+do\b/
          block_stack << :scope_module
          prefix_stack << $1.camelize
          next
        end

        if stripped =~ /\b(resources|resource|member|collection|concern)\s+.*\bdo\b/
          block_stack << :other
        end

        prefix = prefix_stack.any? ? prefix_stack.join("::") + "::" : ""

        if stripped =~ /\bresources\s+(?::|["'])(\w+)/
          resource_name = $1
          controller = "#{prefix}#{resource_name.camelize}Controller"
          actions = parse_route_options($', RESTFUL_ACTIONS)
          register_controller_routes(controller, actions)
          next
        end

        if stripped =~ /\bresource\s+(?::|["'])(\w+)/
          resource_name = $1
          controller = "#{prefix}#{resource_name.camelize}Controller"
          actions = parse_route_options($', SINGULAR_ACTIONS)
          register_controller_routes(controller, actions)
          next
        end

        if stripped =~ /\b(get|post|put|patch|delete|match)\s+["'].*?["'].*\bto:\s*["'](\w+)#(\w+)["']/
          controller = "#{prefix}#{$2.camelize}Controller"
          register_controller_routes(controller, [$3.to_sym])
          next
        end

        if stripped =~ /\b(get|post|put|patch|delete|match)\s+["'].*?["']\s*=>\s*["'](\w+)#(\w+)["']/
          controller = "#{prefix}#{$2.camelize}Controller"
          register_controller_routes(controller, [$3.to_sym])
          next
        end
      end
    end

    def parse_route_options(rest, default_actions)
      if rest =~ /only:\s*\[([^\]]*)\]/
        $1.split(",").map { |s| s.strip.gsub(/[":\[\]']/, "").to_sym } & default_actions
      elsif rest =~ /except:\s*\[([^\]]*)\]/
        default_actions - $1.split(",").map { |s| s.strip.gsub(/[":\[\]']/, "").to_sym }
      else
        default_actions.dup
      end
    end

    def register_controller_routes(controller, actions)
      @routes[controller] = (@routes[controller] || []) + actions
      @routes[controller].uniq!
    end

    def routable_actions_for(controller_name)
      @routes.fetch(controller_name, [])
    end

    def detect_missing_tests
      models = @ast_nodes.select { |n| n[:type] == :model }
      controllers = @ast_nodes.select { |n| n[:type] == :controller }

      models.each do |model_node|
        next if model_node[:model] == "ApplicationRecord"
        expected_spec = "#{File.basename(model_node[:file], '.rb')}_spec.rb"
        has_test = @existing_tests.any? { |t| t[:filename] == expected_spec }

        unless has_test
          suggestions = []
          model_name = model_node[:model]

          if model_node.dig(:metadata, :validations)&.any?
            suggestions << {
              name: "Test active validations",
              type: :validations,
              model: model_name,
              fields: model_node[:metadata][:validations],
              validations: model_node[:metadata][:validations]
            }
          end

          if model_node.dig(:metadata, :associations)&.any?
            assoc_types = model_node[:metadata][:associations].map { |a| a[:type] }.uniq
            assoc_types.each do |assoc_type|
              suggestions << {
                name: "Test #{assoc_type} associations",
                type: assoc_type,
                model: model_name,
                associations: model_node[:metadata][:associations]
              }
            end
          end

          if model_node.dig(:metadata, :scopes)&.any?
            suggestions << {
              name: "Test model scopes",
              type: :scopes,
              model: model_name,
              scopes: model_node[:metadata][:scopes]
            }
          end

          cb = model_node.dig(:metadata, :callbacks) || []
          cb.each do |callback_name|
            suggestions << {
              name: "Test #{callback_name} callback",
              type: callback_name,
              model: model_name,
              callbacks: cb.map { |c| { type: c } }
            }
          end

          if model_node.dig(:metadata, :custom_methods)&.any?
            suggestions << {
              name: "Test custom methods",
              type: :custom_methods,
              model: model_name,
              custom_methods: model_node[:metadata][:custom_methods]
            }
          end

          if model_node.dig(:metadata, :delegation)&.any?
            suggestions << {
              name: "Test delegation",
              type: :delegation,
              model: model_name
            }
          end

          suggestions << {
            name: "Test factory",
            type: :factories,
            model: model_name
          }

          @missing_tests << {
            type: :unit,
            model: model_name,
            file: model_node[:file],
            suggestions: suggestions
          }
        end
      end

      controllers.each do |controller_node|
        controller_name = controller_node[:controller]
        next if controller_name == "ApplicationController"

        expected_spec = "#{File.basename(controller_node[:file], '.rb')}_spec.rb"
        has_test = @existing_tests.any? { |t| t[:filename] == expected_spec }

        unless has_test
          routable = routable_actions_for(controller_name)
          next if @routes_parsed && routable.empty?

          inferred_model = controller_name.sub(/Controller$/, "").singularize

          suggestions = []

          if !@routes_parsed || routable.include?(:index)
            suggestions << {
              name: "Test standard GET #index response parameters",
              type: :get_index,
              controller: controller_name,
              model: inferred_model
            }
          end

          if !@routes_parsed || routable.include?(:create)
            suggestions << {
              name: "Test POST #create branch handling",
              type: :post_create,
              controller: controller_name,
              model: inferred_model
            }
          end

          if !@routes_parsed || routable.include?(:show)
            suggestions << {
              name: "Test GET #show",
              type: :get_show,
              controller: controller_name,
              model: inferred_model
            }
          end

          @missing_tests << {
            type: :request,
            controller: controller_name,
            file: controller_node[:file],
            suggestions: suggestions
          }
        end
      end
    end
  end
end