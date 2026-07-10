require "fileutils"

module ConjureShield
  class TestGenerator
    attr_reader :code, :suggestions

    def initialize(code, suggestions)
      @code = code
      @suggestions = suggestions
      @codebase_path = Dir.pwd
      @framework = nil
    end

    def self.generate(code, suggestions)
      new(code, suggestions).generate_all
    end

    def self.generate_with_path(code, suggestions, codebase_path)
      new(code, suggestions).tap do |g|
        g.instance_variable_set(:@codebase_path, codebase_path)
        g.instance_variable_set(:@framework, nil)
      end.generate_all
    end

    def self.generate_for_all_frameworks(code, suggestions, codebase_path)
      frameworks = []
      frameworks << :rspec if Dir.exist?(File.join(codebase_path, "spec"))
      if Dir.exist?(File.join(codebase_path, "test"))
        frameworks << :minitest
      else
        FileUtils.mkdir_p(File.join(codebase_path, "test"))
        frameworks << :minitest
        puts "Created test/ directory for Minitest"
      end

      frameworks.each_with_index do |fw, idx|
        new(code, suggestions).tap do |g|
          g.instance_variable_set(:@codebase_path, codebase_path)
          g.instance_variable_set(:@framework, fw)
        end.generate_all(skip_factories: idx > 0)
      end
    end

    def generate_all(framework: nil, skip_factories: false)
      @framework = framework if framework
      generate_factories unless skip_factories

      @suggestions.each do |missing_test|
        inner = missing_test[:suggestions] || []
        context = missing_test.reject { |k, _| k == :suggestions }

        inner.each do |suggestion|
          merged = context.merge(suggestion)
          @current_type = merged[:type]
          generate_test(merged)
        end
      end
    end

    def generate_factories
      collect_factory_specs.each do |model_name, info|
        write_factory_file(model_name, factory_content(model_name, info[:columns], info[:associations]))
      end
    end

    def collect_factory_specs
      specs = {}
      @suggestions.each do |missing_test|
        inner = missing_test[:suggestions] || []
        context = missing_test.reject { |k, _| k == :suggestions }
        inner.each do |suggestion|
          next unless suggestion[:type] == :factories

          merged = context.merge(suggestion)
          specs[merged[:model]] = {
            columns: merged[:columns] || {},
            associations: merged[:associations] || []
          }
        end
      end
      specs
    end

    def factory_content(model_name, columns, associations)
      factory_decl = if model_name.include?("::")
        "  factory :#{factory_name(model_name)}, class: \"#{model_name}\" do"
      else
        "  factory :#{factory_name(model_name)} do"
      end

      lines = [
        "# frozen_string_literal: true",
        "",
        "FactoryBot.define do",
        factory_decl,
        factory_attribute_lines(columns),
        factory_association_lines(associations),
        "  end",
        "end",
        "",
      ]
      lines.flatten.join("\n")
    end

    EXCLUDED_FACTORY_COLUMNS = %w[
      id created_at updated_at encrypted_password reset_password_token
      reset_password_sent_at remember_created_at
    ].freeze

    def factory_attribute_lines(columns)
      columns.reject { |name, _| EXCLUDED_FACTORY_COLUMNS.include?(name) }.flat_map do |col_name, col_info|
        line = factory_attribute_line(col_name, col_info[:type])
        line ? "    #{line}" : nil
      end.compact
    end

    def factory_attribute_line(col_name, type)
      case col_name
      when "email", /_email$/
        "sequence(:#{col_name}) { |n| \"user_\#{n}@example.com\" }"
      when /_url$/
        "#{col_name} { \"https://example.com/#{col_name}\" }"
      else
        case type
        when :string then "#{col_name} { \"#{col_name.humanize.downcase}\" }"
        when :text then "#{col_name} { \"sample text\" }"
        when :integer then "#{col_name} { 1 }"
        when :boolean then "#{col_name} { false }"
        when :datetime, :date then "#{col_name} { Time.current }"
        when :decimal, :float then "#{col_name} { 1.0 }"
        else
          nil
        end
      end
    end

    def factory_association_lines(associations)
      associations.flat_map do |assoc|
        name = assoc[:name]
        target = assoc[:target]
        case assoc[:type]
        when :belongs_to
          "    association :#{name}"
        when :has_one, :has_one_through
          [
            "    trait :with_#{name} do",
            "      association :#{name}",
            "    end",
          ]
        when :has_many
          [
            "    trait :with_#{name} do",
            "      association :#{name}",
            "    end",
          ]
        when :has_and_belongs_to_many, :has_many_through
          [
            "    trait :with_#{name} do",
            "      after(:create) do |obj, evaluator|",
            "        obj.#{name} << create(:#{target.underscore})",
            "      end",
            "    end",
          ]
        else
          nil
        end
      end.compact
    end

    def write_factory_file(model_name, content)
      base = @codebase_path || Dir.pwd
      base_dir = File.join(base, rspec? ? "spec" : "test", "factories")
      FileUtils.mkdir_p(base_dir)
      path = File.join(base_dir, "#{factory_name(model_name)}.rb")
      if File.exist?(path)
        puts "Skipped existing factory: #{path}"
        return
      end
      File.write(path, content)
      puts "Generated factory: #{path}"
    end

    private

    def framework
      @framework ||= detect_framework
    end

    def rspec?
      framework == :rspec
    end

    def minitest?
      framework == :minitest
    end

    def detect_framework
      base = @codebase_path || Dir.pwd
      spec_dir = Dir.exist?(File.join(base, "spec"))
      test_dir = Dir.exist?(File.join(base, "test"))
      return :minitest if test_dir && !spec_dir
      :rspec
    end

    def spec_helper_require
      base = @codebase_path || Dir.pwd
      if File.exist?(File.join(base, "spec", "rails_helper.rb"))
        'require "rails_helper"'
      elsif File.exist?(File.join(base, "spec", "spec_helper.rb"))
        'require "spec_helper"'
      elsif rspec?
        'require "rails_helper"'
      else
        'require "test_helper"'
      end
    end

    def write_lines(lines)
      lines.flatten.join("\n") + "\n"
    end

    def devise?
      return @_devise if defined?(@_devise)
      base = @codebase_path || Dir.pwd
      gemfile = File.join(base, "Gemfile")
      @_devise = File.exist?(gemfile) && File.read(gemfile).include?("devise")
    end

    def devise_model_name
      return @_devise_model if defined?(@_devise_model)
      @_devise_model = nil
      models = @code&.select { |f| f[:path].include?("/app/models/") }
      return nil unless models

      models.each do |model|
        if model[:content].include?("devise ") || model[:content].include?("devise\n")
          @_devise_model = model_name_from_path(model[:path])
          break
        end
      end
      @_devise_model || "User"
    end

    def model_name_from_path(path)
      relative = path.sub(%r{.*/app/models/}, "").sub(/\.rb\z/, "")
      relative.split("/").map { |part| part.split("_").map(&:capitalize).join }.join("::")
    end

    def factory_name(model_name)
      model_name.underscore.tr("/", "_")
    end

    def devise_setup(indent: 2, extra_attrs: {})
      return "" unless devise?

      model = devise_model_name
      attrs = {email: "test@example.com", password: "password", password_confirmation: "password"}.merge(extra_attrs)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      pad = " " * indent

      "#{pad}include Devise::Test::IntegrationHelpers\n" \
      "#{pad}let(:current_user) { #{model}.create!(#{attrs_str}) }\n" \
      "#{pad}before { sign_in current_user }\n\n"
    end

    def devise_setup_lines(component: "  ")
      return [] unless devise?

      model = devise_model_name
      attrs = {email: "test@example.com", password: "password", password_confirmation: "password"}
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      [
        "#{component}include Devise::Test::IntegrationHelpers",
        "#{component}let(:current_user) { #{model}.create!(#{attrs_str}) }",
        "#{component}before { sign_in current_user }",
        "",
      ]
    end

    def factory_attributes(model_name, columns: {}, extra_attrs: {})
      suffix = Time.now.to_i.to_s(36) + rand(999).to_s
      excluded = %w[id created_at updated_at encrypted_password reset_password_token reset_password_sent_at remember_created_at]
      hash = columns.reject { |name, _| excluded.include?(name) }.each_with_object({}) do |(col_name, col_info), h|
        value = case col_name
                when "email" then "test#{suffix}@example.com"
                when /_url$/ then "https://example.com/test"
                when /_email$/ then "test#{suffix}@example.com"
                else
                  case col_info[:type]
                  when :string then "#{col_name.humanize.downcase}#{suffix}"
                  when :text then "sample text"
                  when :integer then 1
                  when :boolean then false
                  when :datetime, :date then Time.current
                  when :decimal, :float then 1.0
                  end
                end
        h[col_name.to_sym] = value if value
      end
      if columns.key?("encrypted_password")
        hash[:email] ||= "test#{suffix}@example.com"
        hash[:password] = "password"
        hash[:password_confirmation] = "password"
      end
      hash.merge!(extra_attrs.symbolize_keys) if extra_attrs.any?
      hash
    end

    def prepend_devise(content, model: nil)
      setup = devise_setup
      return content if setup.empty?
      setup + content
    end

    def factory_attrs_str(model_name)
      attrs = factory_attributes(model_name)
      attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
    end

    def controller_factory_attrs(controller)
      model_name = controller[:model]
      columns = controller[:columns] || {}
      attrs = factory_attributes(model_name, columns: columns)
      attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
    end

    def ctrl_base(name)
      name.to_s.sub(/Controller$/, "").underscore.singularize.tr("/", "_")
    end

    def ctrl_route(name)
      ctrl_base(name).pluralize
    end

    def generate_test(suggestion)
      case suggestion[:type]
      when :validations
        minitest? ? generate_minitest_validations(suggestion) : generate_validations_test(suggestion)
      when :validation_messages
        minitest? ? generate_minitest_validations(suggestion) : generate_validation_messages_test(suggestion)
      when :has_one
        minitest? ? generate_minitest_associations(suggestion) : generate_has_one_test(suggestion)
      when :has_many
        minitest? ? generate_minitest_associations(suggestion) : generate_has_many_test(suggestion)
      when :belongs_to
        minitest? ? generate_minitest_associations(suggestion) : generate_belongs_to_test(suggestion)
      when :association_validations
        minitest? ? generate_minitest_associations(suggestion) : generate_association_validations_test(suggestion)
      when :scopes
        minitest? ? generate_minitest_scopes(suggestion) : generate_scopes_test(suggestion)
      when :scoped_arguments
        minitest? ? generate_minitest_scopes(suggestion) : generate_scoped_arguments_test(suggestion)
      when :before_save
        minitest? ? generate_minitest_callbacks(suggestion) : generate_before_save_test(suggestion)
      when :after_save
        minitest? ? generate_minitest_callbacks(suggestion) : generate_after_save_test(suggestion)
      when :before_destroy
        minitest? ? generate_minitest_callbacks(suggestion) : generate_before_destroy_test(suggestion)
      when :after_destroy
        minitest? ? generate_minitest_callbacks(suggestion) : generate_after_destroy_test(suggestion)
      when :custom_methods
        minitest? ? generate_minitest_custom_methods(suggestion) : generate_custom_methods_test(suggestion)
      when :factories
        minitest? ? generate_minitest_factories(suggestion) : generate_factories_test(suggestion)
      when :serialization
        minitest? ? generate_minitest_serialization(suggestion) : generate_serialization_test(suggestion)
      when :delegation
        minitest? ? generate_minitest_serialization(suggestion) : generate_delegation_test(suggestion)
      when :get_index
        minitest? ? generate_minitest_request_test(suggestion) : generate_get_index_test(suggestion)
      when :post_create
        minitest? ? generate_minitest_request_test(suggestion) : generate_post_create_valid_test(suggestion)
      when :get_show
        minitest? ? generate_minitest_request_test(suggestion) : generate_get_show_test(suggestion)
      when :index_pagination
        minitest? ? generate_minitest_request_test(suggestion) : generate_index_pagination_test(suggestion)
      when :index_sorting
        minitest? ? generate_minitest_request_test(suggestion) : generate_index_sorting_test(suggestion)
      when :show_with_associations
        minitest? ? generate_minitest_request_test(suggestion) : generate_show_with_associations_test(suggestion)
      when :get_new
        minitest? ? generate_minitest_request_test(suggestion) : generate_get_new_test(suggestion)
      when :new_form
        minitest? ? generate_minitest_request_test(suggestion) : generate_new_form_test(suggestion)
      when :get_edit
        minitest? ? generate_minitest_request_test(suggestion) : generate_get_edit_test(suggestion)
      when :edit_form
        minitest? ? generate_minitest_request_test(suggestion) : generate_edit_form_test(suggestion)
      when :post_create_valid
        minitest? ? generate_minitest_request_test(suggestion) : generate_post_create_valid_test(suggestion)
      when :post_create_invalid
        minitest? ? generate_minitest_request_test(suggestion) : generate_post_create_invalid_test(suggestion)
      when :post_create_redirect
        minitest? ? generate_minitest_request_test(suggestion) : generate_post_create_redirect_test(suggestion)
      when :put_patch_update_valid
        minitest? ? generate_minitest_request_test(suggestion) : generate_put_patch_update_valid_test(suggestion)
      when :put_patch_update_invalid
        minitest? ? generate_minitest_request_test(suggestion) : generate_put_patch_update_invalid_test(suggestion)
      when :put_patch_update_redirect
        minitest? ? generate_minitest_request_test(suggestion) : generate_put_patch_update_redirect_test(suggestion)
      when :delete_destroy
        minitest? ? generate_minitest_request_test(suggestion) : generate_delete_destroy_test(suggestion)
      when :delete_destroy_redirect
        minitest? ? generate_minitest_request_test(suggestion) : generate_delete_destroy_redirect_test(suggestion)
      when :strong_parameters_permit
        minitest? ? generate_minitest_request_test(suggestion) : generate_strong_parameters_permit_test(suggestion)
      when :strong_parameters_deny
        minitest? ? generate_minitest_request_test(suggestion) : generate_strong_parameters_deny_test(suggestion)
      when :flash_messages
        minitest? ? generate_minitest_request_test(suggestion) : generate_flash_messages_test(suggestion)
      when :redirects
        minitest? ? generate_minitest_request_test(suggestion) : generate_redirects_test(suggestion)
      when :json_responses
        minitest? ? generate_minitest_request_test(suggestion) : generate_json_responses_test(suggestion)
      when :create_view, :edit_update, :delete, :view_details
        minitest? ? generate_minitest_request_test(suggestion) : generate_integration_test(suggestion)
      when :get_list, :get_single, :put_update
        minitest? ? generate_minitest_request_test(suggestion) : generate_api_test(suggestion)
      when :create_view_feature, :edit_feature, :delete_feature, :view_details_feature
        minitest? ? generate_minitest_request_test(suggestion) : generate_feature_test(suggestion)
      when :stimulus
        minitest? ? generate_minitest_request_test(suggestion) : generate_stimulus_test(suggestion)
      when :cable
        minitest? ? generate_minitest_request_test(suggestion) : generate_cable_test(suggestion)
      end
    end

    private

    def generate_stimulus_test(suggestion)
      controller = suggestion[:controller]
      targets = suggestion[:targets] || []
      values = suggestion[:values] || {}
      classes = suggestion[:classes] || []
      actions = suggestion[:actions] || []

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe \"##{controller}\", type: :stimulus do",
        "  describe \"lifecycle\" do",
        "    it \"connects without error\" do",
        "      controller = #{controller.camelize}Controller.new",
        "      expect { controller.connect() }.not_to raise_error",
        "    end",
        "",
        "    it \"disconnects without error\" do",
        "      controller = #{controller.camelize}Controller.new",
        "      expect { controller.disconnect() }.not_to raise_error",
        "    end",
        "  end",
        "",
      ]

      if targets.any?
        lines << "  describe \"targets\" do"
        targets.each do |target|
          lines << "    it \"has a #{target} target\" do"
          lines << "      expect(controller).to respond_to(:#{target}_target)"
          lines << "    end"
          lines << ""
        end
        lines << "  end"
        lines << ""
      end

      if values.any?
        lines << "  describe \"values\" do"
        values.each do |name, type|
          lines << "    it \"has #{name} value\" do"
          lines << "      expect(controller).to respond_to(:#{name})"
          lines << "    end"
          lines << ""
        end
        lines << "  end"
        lines << ""
      end

      if classes.any?
        lines << "  describe \"CSS classes\" do"
        classes.each do |cls|
          lines << "    it \"has #{cls} CSS class\" do"
          lines << "      expect(controller).to respond_to(:#{cls}_class)"
          lines << "    end"
          lines << ""
        end
        lines << "  end"
        lines << ""
      end

      if actions.any?
        lines << "  describe \"actions\" do"
        actions.each do |action|
          lines << "    it \"responds to #{action}\" do"
          lines << "      expect(controller).to respond_to(:#{action})"
          lines << "    end"
          lines << ""
        end
        lines << "  end"
        lines << ""
      end

      lines << "end"
      lines << ""

      write_test_file(controller, lines.join("\n"))
    end

    def generate_cable_test(suggestion)
      channel = suggestion[:channel]

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "ApplicationCable::#{channel}", type: :cable do
          let(:connection) { ApplicationCable::Connection.new }
          let(:subscription) { connection.subscriptions["#{channel}"] }

          describe "connection" do
            it "connects successfully" do
              expect {
                connection.connect
              }.to change { connection.subscriptions }.from({}).to({})
            end

            it "disconnects successfully" do
              connection.connect
              expect {
                connection.disconnect
              }.to change { connection.subscriptions }.to({})
            end
          end

          describe "subscriptions" do
            it "subscribes to #{channel}" do
              expect(subscription).to receive(:subscribe)
              connection.subscribe("#{channel}")
            end

            it "unsubscribes from #{channel}" do
              expect(subscription).to receive(:unsubscribe)
              connection.unsubscribe("#{channel}")
            end
          end

          describe "broadcast" do
            it "broadcasts to #{channel}" do
              expect(subscription).to receive(:broadcast)
              connection.broadcast_to(subscription, { message: "test" })
            end
          end

          describe "stream_from" do
            it "streams from #{channel}" do
              expect(subscription).to receive(:stream_from)
              connection.stream_from(subscription, :event)
            end
          end

          describe "presence" do
            it "handles presence subscriptions" do
              expect(subscription).to receive(:presence)
              connection.presence(subscription)
            end

            it "handles leave subscriptions" do
              expect(subscription).to receive(:leave)
              connection.leave(subscription)
            end
          end
        end
      TEST

      write_test_file(channel, test_content)
    end

    def generate_validations_test(model)
      fields = model[:fields]
      validations = model[:validations]
      model_name = model[:model]

      inner = validations.flat_map do |validation|
        generate_validation_context(validation) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"validations\" do",
        inner,
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_validation_context(validation)
      field = validation[:field]
      validators = validation[:validators] || []

      matchers = validators.map do |v|
        case v.to_s.downcase
        when "presence"
          "      it { is_expected.to validate_presence_of(:#{field}) }"
        when "uniqueness"
          "      it { is_expected.to validate_uniqueness_of(:#{field}) }"
        when "length"
          "      it { is_expected.to validate_length_of(:#{field}) }"
        when "inclusion"
          "      it { is_expected.to validate_inclusion_of(:#{field}).in_array([]) }"
        when "format"
          "      it { is_expected.to allow_value(\"value\").for(:#{field}) }"
        when "numericality"
          "      it { is_expected.to validate_numericality_of(:#{field}) }"
        else
          "      it { is_expected.to validate_presence_of(:#{field}) }"
        end
      end

      [
        "    context \"validates #{field}\" do",
        matchers,
        "    end",
      ]
    end

    def generate_validation_messages_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "validation error messages" do
            it "returns custom error messages" do
              record = build(:#{model[:model].downcase}, invalid_data: "value")
              expect(record.errors.full_messages).to be_present
            end

            it "returns I18n localized messages" do
              record = build(:#{model[:model].downcase}, invalid_data: "value")
              expect(record.errors.full_messages).to be_present
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_has_one_test(model)
      associations = model[:associations].select { |a| a[:type] == :has_one }
      model_name = model[:model]

      inner = associations.flat_map do |assoc|
        generate_has_one_context(assoc) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"associations\" do",
        "    context \"has_one associations\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_has_one_context(assoc)
      target = assoc[:target]

      [
        "      it { is_expected.to have_one(:#{target.downcase}) }",
      ]
    end

    def generate_has_many_test(model)
      associations = model[:associations].select { |a| a[:type] == :has_many }
      model_name = model[:model]

      inner = associations.flat_map do |assoc|
        generate_has_many_context(assoc) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"associations\" do",
        "    context \"has_many associations\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_has_many_context(assoc)
      target = assoc[:target]

      [
        "      it { is_expected.to have_many(:#{target.downcase.pluralize}) }",
      ]
    end

    def generate_belongs_to_test(model)
      associations = model[:associations].select { |a| a[:type] == :belongs_to }
      model_name = model[:model]

      inner = associations.flat_map do |assoc|
        generate_belongs_to_context(assoc) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"associations\" do",
        "    context \"belongs_to associations\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_belongs_to_context(assoc)
      target = assoc[:target]

      [
        "      it { is_expected.to belong_to(:#{target.downcase}) }",
      ]
    end

    def generate_association_validations_test(model)
      associations = model[:associations]
      model_name = model[:model]

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"associations\" do",
        "    context \"association validations\" do",
        "      it \"validates associated #{model_name.downcase.pluralize} are valid\" do",
        "        record = #{model_name}.new",
        "        record.valid?",
        "        expect(record.errors).to be_present",
        "      end",
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_scopes_test(model)
      scopes = model[:scopes]
      model_name = model[:model]
      columns = model[:columns] || {}

      scope_tests = scopes.flat_map do |scope|
        generate_scope_lines(scope, model_name, columns: columns) + [""]
      end
      scope_tests.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"scopes\" do",
        scope_tests,
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_scope_lines(scope, model_name, columns: {})
      name = scope[:name]

      extra = {}
      boolean_cols = columns.select { |_, ci| ci[:type] == :boolean }.keys
      if boolean_cols.include?(name.to_s)
        extra[name.to_sym] = true
      elsif name.to_s == "active" && boolean_cols.include?("deleted")
        extra[:deleted] = false
      elsif name.to_s == "deleted" && boolean_cols.include?("deleted")
        extra[:deleted] = true
      end
      attrs = factory_attributes(model_name, columns: columns, extra_attrs: extra)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")

      [
        "    it \"returns #{name} results\" do",
        "      record = described_class.create!(#{attrs_str})",
        "      expect(described_class.#{name}).to be_present",
        "    end",
      ]
    end

    def generate_scoped_arguments_test(model)
      scopes = model[:scopes]
      model_name = model[:model]

      inner = scopes.flat_map do |scope|
        generate_scoped_arguments_context(scope, model_name) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"scopes with arguments\" do",
        inner,
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_scoped_arguments_context(scope, model_name)
      name = scope[:name]
      args = scope[:args]

      [
        "    it \"accepts #{name} with #{args.join(", ")}\" do",
        "      expect(described_class.#{name}(#{args.join(", ")})).to be_present",
        "    end",
      ]
    end

    def generate_before_save_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :before_save }
      model_name = model[:model]
      columns = model[:columns] || {}

      inner = callbacks.flat_map do |cb|
        generate_before_save_context(cb, model_name, columns: columns) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"callbacks\" do",
        "    context \"before_save callbacks\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_before_save_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      [
        "      it \"executes before_save callback\" do",
        "        #{var} = described_class.new(#{attrs_str})",
        "        expect { #{var}.save(validate: false) }.not_to raise_error",
        "      end",
      ]
    end

    def generate_after_save_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :after_save }
      model_name = model[:model]
      columns = model[:columns] || {}

      inner = callbacks.flat_map do |cb|
        generate_after_save_context(cb, model_name, columns: columns) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"callbacks\" do",
        "    context \"after_save callbacks\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_after_save_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      [
        "      it \"executes after_save callback\" do",
        "        #{var} = described_class.new(#{attrs_str})",
        "        expect { #{var}.save }.not_to raise_error",
        "      end",
      ]
    end

    def generate_before_destroy_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :before_destroy }
      model_name = model[:model]
      columns = model[:columns] || {}

      inner = callbacks.flat_map do |cb|
        generate_before_destroy_context(cb, model_name, columns: columns) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"callbacks\" do",
        "    context \"before_destroy callbacks\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_before_destroy_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      [
        "      it \"executes before_destroy callback\" do",
        "        #{var} = described_class.new(#{attrs_str})",
        "        expect { #{var}.destroy }.not_to raise_error",
        "      end",
      ]
    end

    def generate_after_destroy_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :after_destroy }
      model_name = model[:model]
      columns = model[:columns] || {}

      inner = callbacks.flat_map do |cb|
        generate_after_destroy_context(cb, model_name, columns: columns) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"callbacks\" do",
        "    context \"after_destroy callbacks\" do",
        inner,
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_after_destroy_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      [
        "      it \"executes after_destroy callback\" do",
        "        #{var} = described_class.new(#{attrs_str})",
        "        expect { #{var}.destroy }.not_to raise_error",
        "      end",
      ]
    end

    def generate_custom_methods_test(model)
      methods = model[:custom_methods]
      model_name = model[:model]
      columns = model[:columns] || {}

      inner = methods.flat_map do |m|
        generate_custom_method_test(m, model_name, columns: columns) + [""]
      end
      inner.pop

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name}, type: :model do",
        "  describe \"custom methods\" do",
        inner,
        "  end",
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_custom_method_test(method, model_name, columns: {})
      name = method.is_a?(Hash) ? method[:name] : method
      is_class_method = method.is_a?(Hash) && method[:class_method]
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")

      receiver = is_class_method ? "described_class" : "described_class.new(#{attrs_str})"

      matcher = case name.to_s
                when /\?$/ then "be(true).or be(false)"
                when /^ransackable/ then "be_a(Array)"
                else "be_present"
                end

      [
        "    it \"returns #{name} result\" do",
        "      expect(#{receiver}.#{name}).to #{matcher}",
        "    end",
      ]
    end

    def generate_factories_test(model)
      model_name = model[:model]

      inner = [
        "  it \"has a valid factory\" do",
        "    expect(build(:#{factory_name(model_name)})).to be_valid",
        "  end",
      ]

      lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe #{model_name} do",
        inner,
        "end",
        "",
      ]

      write_test_file(model_name, write_lines(lines))
    end

    def generate_serialization_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "serialization" do
            it "serializes to JSON" do
              expect(build(:#{factory_name(model[:model])}).to_json).to be_present
            end

            it "serializes to YAML" do
              expect(build(:#{factory_name(model[:model])}).to_yaml).to be_present
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_delegation_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "delegation" do
            it "delegates method to association" do
              expect(build(:#{factory_name(model[:model])})).to delegate(:method_name).to(:association_name)
            end

            it "delegates method with prefix" do
              expect(build(:#{factory_name(model[:model])})).to delegate(:method_name).to(:association_name, prefix: true)
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_get_index_test(controller)
      route_plural = ctrl_route(controller[:controller])
      model_name = controller[:model]
      columns = controller[:columns] || {}

      attrs1 = factory_attributes(model_name, columns: columns)
      attrs2 = factory_attributes(model_name, columns: columns)
      attrs1_str = attrs1.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      attrs2_str = attrs2.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")

      test_lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe \"#{controller[:controller]}\", type: :request do",
      ]

      if devise?
        test_lines << "  include Devise::Test::IntegrationHelpers"
        model = devise_model_name
        attrs = {email: "test@example.com", password: "password", password_confirmation: "password"}
        attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        test_lines << "  let(:current_user) { #{model}.create!(#{attrs_str}) }"
        test_lines << "  before { sign_in current_user }"
        test_lines << ""
      end

      test_lines += [
        "  describe \"GET index action\" do",
        "    let!(:record1) { #{model_name}.create!(#{attrs1_str}) }",
        "    let!(:record2) { #{model_name}.create!(#{attrs2_str}) }",
        "",
        "    it \"returns success response\" do",
        "      get #{route_plural}_path",
        "      expect(response).to have_http_status(:ok)",
        "    end",
        "",
        "    it \"renders index template\" do",
        "      get #{route_plural}_path",
        "      expect(response).to render_template(:index)",
        "    end",
        "",
        "    it \"passes correct instance variables\" do",
        "      get #{route_plural}_path",
        "      expect(assigns(:#{route_plural})).to be_present",
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(controller[:controller], write_lines(test_lines))
    end

    def generate_index_pagination_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET index action" do
            context "with pagination" do
              it "returns paginated results" do
                get #{ctrl_route(controller[:controller])}_path
                expect(response).to have_http_status(:ok)
              end

              it "passes page parameter" do
                get "#{ctrl_route(controller[:controller])}_path?page=2"
                expect(response).to have_http_status(:ok)
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_index_sorting_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET index action" do
            context "with sorting" do
              it "sorts by default" do
                get #{ctrl_route(controller[:controller])}_path
                expect(response).to have_http_status(:ok)
              end

              it "sorts by custom parameter" do
                get "#{ctrl_route(controller[:controller])}_path?sort=field"
                expect(response).to have_http_status(:ok)
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_get_show_test(controller)
      singular = ctrl_base(controller[:controller])
      route_param = controller[:route_param]
      model_name = controller[:model]
      columns = controller[:columns] || {}
      attrs_str = factory_attributes(model_name, columns: columns).map { |k, v| "#{k}: #{v.inspect}" }.join(", ")

      show_path_arg = route_param ? "record.#{route_param}" : "record"

      test_lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe \"#{controller[:controller]}\", type: :request do",
      ] + devise_setup_lines + [
        "  describe \"GET show action\" do",
        "    let!(:record) { #{model_name}.create!(#{attrs_str}) }",
        "",
        "    it \"returns success response\" do",
        "      get #{singular}_path(#{show_path_arg})",
        "      expect(response).to have_http_status(:ok)",
        "    end",
        "",
        "    it \"renders show template\" do",
        "      get #{singular}_path(#{show_path_arg})",
        "      expect(response).to render_template(:show)",
        "    end",
        "",
        "    it \"passes correct instance variables\" do",
        "      get #{singular}_path(#{show_path_arg})",
        "      expect(assigns(:#{singular})).to be_present",
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file(controller[:controller], write_lines(test_lines))
    end

    def generate_show_with_associations_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET show action" do
            context "with associations" do
              it "includes associated records" do
                get #{ctrl_base(controller[:controller]).singularize}_path(1)
                expect(response).to have_http_status(:ok)
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_get_new_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET new action" do
            it "returns success response" do
              get new_#{ctrl_base(controller[:controller])}_path
              expect(response).to have_http_status(:ok)
            end

            it "renders new template" do
              get "new_#{ctrl_base(controller[:controller])}_path"
              expect(response).to render_template(:new)
            end

            it "passes correct instance variables" do
              get "new_#{ctrl_base(controller[:controller])}_path"
              expect(assigns(:#{ctrl_base(controller[:controller])})).to be_a(#{ctrl_base(controller[:controller]).camelize})
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_new_form_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET new action" do
            context "form rendering" do
              it "renders form with all fields" do
                get "new_#{ctrl_base(controller[:controller])}_path"
                expect(response).to render_template(:new)
              end

              it "includes all form fields" do
                get "new_#{ctrl_base(controller[:controller])}_path"
                expect(response.body).to include("form")
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_get_edit_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET edit action" do
            it "returns success response" do
              get edit_#{ctrl_base(controller[:controller])}_path(1)
              expect(response).to have_http_status(:ok)
            end

            it "renders edit template" do
              get "edit_#{ctrl_base(controller[:controller])}_path/#{ctrl_base(controller[:controller])}_id"
              expect(response).to render_template(:edit)
            end

            it "passes correct instance variables" do
              get "edit_#{ctrl_base(controller[:controller])}_path/#{ctrl_base(controller[:controller])}_id"
              expect(assigns(:#{ctrl_base(controller[:controller])})).to be_a(#{ctrl_base(controller[:controller]).camelize})
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_edit_form_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET edit action" do
            context "form rendering" do
              it "renders form with pre-filled data" do
                get "edit_#{ctrl_base(controller[:controller])}_path/#{ctrl_base(controller[:controller])}_id"
                expect(response).to render_template(:edit)
              end

              it "includes pre-filled form fields" do
                get "edit_#{ctrl_base(controller[:controller])}_path/#{ctrl_base(controller[:controller])}_id"
                expect(response.body).to include("form")
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_post_create_valid_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "POST create action" do
            context "with valid parameters" do
              it "creates new record" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_create_params(controller)}
                  }
                }
                expect(response).to have_http_status(:created)
              end

              it "redirects to new record" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_create_params(controller)}
                  }
                }
                expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
              end

              it "assigns correct instance variables" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_create_params(controller)}
                  }
                }
                expect(assigns(:#{ctrl_base(controller[:controller])})).to be_a(#{ctrl_base(controller[:controller]).camelize})
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_create_params(controller)
      controller_factory_attrs(controller)
    end

    def generate_invalid_params(controller)
      columns = controller[:columns] || {}
      first = columns.keys.first
      return "invalid_field: \"\"" unless first

      "#{first}: \"\""
    end

    def generate_post_create_invalid_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "POST create action" do
            context "with invalid parameters" do
              it "returns validation errors" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_invalid_params(controller)}
                  }
                }
                expect(response).to have_http_status(:unprocessable_entity)
              end

              it "renders new template with errors" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_invalid_params(controller)}
                  }
                }
                expect(response).to render_template(:new)
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_post_create_redirect_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "POST create action" do
            context "with redirect" do
              it "redirects to new record" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_create_params(controller)}
                  }
                }
                expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
              end

              it "sets flash messages" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_create_params(controller)}
                  }
                }
                expect(flash[:notice]).to be_present
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_put_patch_update_valid_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "PUT/PATCH update action" do
            context "with valid parameters" do
              it "updates the record" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_update_params(controller)}
                  }
                }
                expect(response).to have_http_status(:ok)
              end

              it "redirects to updated record" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_update_params(controller)}
                  }
                }
                expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
              end

              it "updates the record in database" do
                record = create(:#{factory_name(controller[:model])})
                new_attrs = attributes_for(:#{factory_name(controller[:model])})
                put #{ctrl_base(controller[:controller]).singularize}_path(record.id), params: {
                  "#{ctrl_base(controller[:controller])}": new_attrs
                }
                record.reload
                expect(record).to have_attributes(new_attrs)
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_update_params(controller)
      controller_factory_attrs(controller)
    end

    def generate_put_patch_update_invalid_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "PUT/PATCH update action" do
            context "with invalid parameters" do
              it "returns validation errors" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_invalid_params(controller)}
                  }
                }
                expect(response).to have_http_status(:unprocessable_entity)
              end

              it "renders edit template with errors" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_invalid_params(controller)}
                  }
                }
                expect(response).to render_template(:edit)
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_put_patch_update_redirect_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "PUT/PATCH update action" do
            context "with redirect" do
              it "redirects to updated record" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_update_params(controller)}
                  }
                }
                expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
              end

              it "sets flash messages" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_update_params(controller)}
                  }
                }
                expect(flash[:notice]).to be_present
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_delete_destroy_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "DELETE destroy action" do
              it "deletes the record" do
                delete #{ctrl_base(controller[:controller]).singularize}_path(1)
              expect(response).to have_http_status(:no_content)
            end

            it "removes the record from database" do
              record = create(:#{factory_name(controller[:model])})
              expect {
                delete #{ctrl_base(controller[:controller]).singularize}_path(record.id)
              }.to change(#{ctrl_route(controller[:controller])}, :count).by(-1)
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_delete_destroy_redirect_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "DELETE destroy action" do
            context "with redirect" do
              it "redirects after destroy" do
                delete #{ctrl_base(controller[:controller]).singularize}_path(1)
                expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
              end

              it "sets flash messages" do
                delete #{ctrl_base(controller[:controller]).singularize}_path(1)
                expect(flash[:notice]).to be_present
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_strong_parameters_permit_test(controller)
      factory = factory_name(controller[:model])
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "strong parameters" do
            it "persists submitted attributes on create" do
              expect {
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": attributes_for(:#{factory})
                }
              }.to change(#{ctrl_route(controller[:controller])}, :count).by(1)
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_strong_parameters_deny_test(controller)
      factory = factory_name(controller[:model])
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "strong parameters" do
            it "ignores non-permitted attributes" do
              post #{ctrl_route(controller[:controller])}_path, params: {
                "#{ctrl_base(controller[:controller])}": attributes_for(:#{factory}).merge(admin: true)
              }
              expect(#{ctrl_route(controller[:controller])}.last.attributes["admin"]).to be_nil.or be_falsy
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_flash_messages_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "flash messages" do
            it "sets notice flash" do
              post #{ctrl_route(controller[:controller])}_path, params: {
                "#{ctrl_base(controller[:controller])}": {
                  #{generate_create_params(controller)}
                }
              }
              expect(flash[:notice]).to be_present
            end

            it "sets alert flash" do
              post #{ctrl_route(controller[:controller])}_path, params: {
                "#{ctrl_base(controller[:controller])}": {
                  #{generate_invalid_params(controller)}
                }
              }
              expect(flash[:alert]).to be_present
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_redirects_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "redirects" do
            it "redirects to new record" do
              post #{ctrl_route(controller[:controller])}_path, params: {
                "#{ctrl_base(controller[:controller])}": {
                  #{generate_create_params(controller)}
                }
              }
              expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
            end

            it "redirects to edit record" do
              put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                "#{ctrl_base(controller[:controller])}": {
                  #{generate_update_params(controller)}
                }
              }
              expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_json_responses_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "JSON responses" do
            it "returns JSON for show action" do
              get #{ctrl_base(controller[:controller]).singularize}_path(1), headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body).to be_a(Hash)
            end

            it "returns JSON for create action" do
              post #{ctrl_route(controller[:controller])}_path, params: {
                "#{ctrl_base(controller[:controller])}": {
                  #{generate_create_params(controller)}
                }
              }, headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:created)
              expect(response.parsed_body).to be_a(Hash)
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_integration_test(suggestion)
      controller = suggestion[:controller]
      model = suggestion[:model]

      test_lines = [
        "# frozen_string_literal: true",
        "",
        spec_helper_require,
        "",
        "RSpec.describe \"#{ctrl_base(controller).capitalize}\", type: :request do",
      ] + devise_setup_lines + [
        "  describe \"user workflow\" do",
        "    context \"create and view\" do",
        "      it \"creates a new #{model} and redirects to show\" do",
        "        post #{ctrl_route(controller)}_path, params: {",
        "          \"#{ctrl_base(controller)}\": {",
        "            id: 1, #{ctrl_base(controller)}: { name: \"Test\" }",
        "          }",
        "        }",
        "        expect(response).to redirect_to(#{ctrl_route(controller)}_path)",
        "        expect(flash[:notice]).to be_present",
        "      end",
        "",
        "      it \"displays the created #{model} with all attributes\" do",
        "        post #{ctrl_route(controller)}_path, params: {",
        "          \"#{ctrl_base(controller)}\": {",
        "            id: 1, #{ctrl_base(controller)}: { name: \"Test\" }",
        "          }",
        "        }",
        "        follow_redirect!",
        "        expect(response).to have_http_status(:ok)",
        "        expect(page).to have_content(/#{model}/i)",
        "      end",
        "    end",
        "",
        "    context \"edit and update\" do",
        "      it \"edits the #{model} and saves changes\" do",
        "        put #{ctrl_base(controller).singularize}_path(1), params: {",
        "          \"#{ctrl_base(controller)}\": {",
        "            id: 1, #{ctrl_base(controller)}: { name: \"Updated\" }",
        "          }",
        "        }",
        "        expect(response).to redirect_to(#{ctrl_base(controller)}_path)",
        "        expect(flash[:notice]).to be_present",
        "      end",
        "",
        "      it \"displays the updated #{model} with new values\" do",
        "        put #{ctrl_base(controller).singularize}_path(1), params: {",
        "          \"#{ctrl_base(controller)}\": {",
        "            id: 1, #{ctrl_base(controller)}: { name: \"Updated\" }",
        "          }",
        "        }",
        "        follow_redirect!",
        "        expect(response).to have_http_status(:ok)",
        "        expect(page).to have_content(/Updated/i)",
        "      end",
        "    end",
        "",
        "    context \"delete\" do",
        "      it \"deletes the #{model} and redirects to index\" do",
        "        delete #{ctrl_base(controller).singularize}_path(1)",
        "        expect(response).to redirect_to(#{ctrl_base(controller)}_path)",
        "        expect(flash[:notice]).to be_present",
        "      end",
        "    end",
        "  end",
        "end",
        "",
      ]

      write_test_file("#{controller}_integration", write_lines(test_lines))
    end

    def write_test_file(subject, content)
      base = @codebase_path || Dir.pwd
      base_dir = File.join(base, rspec? ? "spec" : "test")
      FileUtils.mkdir_p(base_dir)
      ext = rspec? ? "_spec.rb" : "_test.rb"
      basename = subject.to_s.underscore.tr("/", "_")
      suffix = @current_type
      test_path = File.join(base_dir, "#{basename}_#{suffix}#{ext}")

      commented = content.lines.map { |line|
        if line.strip.empty?
          "#\n"
        elsif line.start_with?("#")
          "##{line}"
        else
          "# #{line}"
        end
      }.join
      File.write(test_path, commented)
      puts "Generated example: #{test_path}"
    end

    def generate_api_test(suggestion)
      controller = suggestion[:controller]
      model = suggestion[:model]

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{ctrl_base(controller).capitalize}", type: :api do
          describe "GET /#{ctrl_route(controller)}" do
            it "returns 200 and list of #{model.pluralize}" do
              get #{ctrl_route(controller)}_path
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body).to be_a(Array)
              expect(response.parsed_body).to all(be_a(#{model}))
            end

            it "returns 401 when not authenticated" do
              get #{ctrl_route(controller)}_path
              expect(response).to have_http_status(:unauthorized)
            end
          end

          describe "POST /#{ctrl_route(controller)}" do
            context "with valid payload" do
              it "creates a new #{model} and returns 201" do
                post #{ctrl_route(controller)}_path,
                     params: {
                       "#{ctrl_base(controller)}": {
                         id: 1, #{ctrl_base(controller)}: { name: "Test" }
                       }
                     },
                     headers: { "Accept" => "application/json" }
                expect(response).to have_http_status(:created)
                expect(response.parsed_body[:id]).to be_present
                expect(response.parsed_body[:#{ctrl_base(controller)}]).to be_a(Hash)
              end
            end

            context "with invalid payload" do
              it "returns 422 with validation errors" do
                post #{ctrl_route(controller)}_path,
                     params: {
                       "#{ctrl_base(controller)}": {
                         #{generate_invalid_params(controller)}
                       }
                     },
                     headers: { "Accept" => "application/json" }
                expect(response).to have_http_status(:unprocessable_entity)
                expect(response.parsed_body[:errors]).to be_a(Hash)
              end
            end
          end

          describe "GET /#{ctrl_route(controller)}/:id" do
            it "returns the #{model} with all attributes" do
              get #{ctrl_base(controller).singularize}_path(1),
                  headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body).to be_a(Hash)
              expect(response.parsed_body[:id]).to eq(1)
            end

            it "returns 404 for non-existent #{model}" do
              get #{ctrl_base(controller).singularize}_path(999),
                  headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:not_found)
            end
          end

          describe "PUT /#{ctrl_route(controller)}/:id" do
            it "updates the #{model} and returns 200" do
          put #{ctrl_base(controller).singularize}_path(1),
              params: {
                    "#{ctrl_base(controller)}": {
                      id: 1, #{ctrl_base(controller)}: { name: "Updated" }
                    }
                  },
                  headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body[:id]).to eq(1)
            end
          end

          describe "DELETE /#{ctrl_route(controller)}/:id" do
            it "deletes the #{model} and returns 204" do
              delete #{ctrl_base(controller).singularize}_path(1),
                     headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:no_content)
            end
          end
        end
      TEST

      write_test_file("#{controller}_api", test_content)
    end

    def generate_feature_test(suggestion)
      controller = suggestion[:controller]
      model = suggestion[:model]

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller}/#{controller}", type: :feature do
          let(:#{factory_name(model)}) { create(:#{factory_name(model)}) }

          describe "user story: Create and view #{model}" do
            it "allows users to create a new #{model} and see it on the dashboard" do
              visit #{ctrl_route(controller)}_path
              within("form") do
                fill_in "#{ctrl_base(controller)} Name", with: "Test #{model}"
                click_button "Create #{model}"
              end
              expect(page).to have_content("#{model} was successfully created.")
              expect(page).to have_content("Test #{model}")
            end
          end

          describe "user story: Edit #{model}" do
            it "allows users to edit an existing #{model}" do
              visit #{ctrl_route(controller)}_path
              click_link "Edit #{model}", match: :first
              within("form") do
                fill_in "#{ctrl_base(controller)} Name", with: "Updated #{model}"
                click_button "Update #{model}"
              end
              expect(page).to have_content("#{model} was successfully updated.")
              expect(page).to have_content("Updated #{model}")
            end
          end

          describe "user story: Delete #{model}" do
            it "allows users to delete a #{model}" do
              visit #{ctrl_route(controller)}_path
              within(first(%(a[href*="/#{ctrl_route(controller)}/1"]))) do
                click_link "Delete #{model}"
              end
              expect(page).to have_content("#{model} was successfully deleted.")
            end
          end

          describe "user story: View #{model} details" do
            it "displays all #{model} information on the show page" do
              visit #{ctrl_route(controller)}_path(#{model}.id)
              expect(page).to have_content("Show #{model}")
              expect(page).to have_content("#{model} Name")
              expect(page).to have_content("#{model} Email")
            end
          end
        end
      TEST

      write_test_file("#{controller}_feature", test_content)
    end

    # === Minitest generation methods ===

    def generate_minitest_validations(suggestion)
      model_name = suggestion[:model]
      fields = suggestion[:fields] || []

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          #{fields.map { |f| minitest_validation_test(f, model_name) }.join("\n")}
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def minitest_validation_test(field, model_name)
      if field.is_a?(Hash)
        fname = field[:field]
      else
        fname = field
      end

      <<~MINITEST
        test "validates #{fname}" do
          record = #{model_name}.new
          record.valid?
          assert_not record.errors[:#{fname}].empty?, "#{fname} should be validated"
        end
      MINITEST
    end

    def generate_minitest_associations(suggestion)
      model_name = suggestion[:model]
      assocs = suggestion[:associations] || []

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          #{assocs.map { |a| minitest_association_test(a, model_name) }.join("\n")}
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def minitest_association_test(assoc, model_name)
      type = assoc[:type]
      target = assoc[:target]
      var = model_name.underscore

      <<~MINITEST
        test "should #{type} #{target}" do
          #{var} = #{model_name}.new
          assert_respond_to #{var}, :#{target.underscore}
        end
      MINITEST
    end

    def generate_minitest_scopes(suggestion)
      model_name = suggestion[:model]
      scopes = suggestion[:scopes] || []

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          #{scopes.map { |s| minitest_scope_test(s, model_name) }.join("\n")}
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def minitest_scope_test(scope, model_name)
      name = scope[:name]
      table = model_name.underscore.pluralize

      <<~MINITEST
        test "#{name} scope returns results" do
          assert_respond_to #{model_name}, :#{name}
        end
      MINITEST
    end

    def generate_minitest_callbacks(suggestion)
      model_name = suggestion[:model]
      cbs = suggestion[:callbacks] || []

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          #{cbs.map { |cb| minitest_callback_test(cb, model_name) }.join("\n")}
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def minitest_callback_test(callback, model_name)
      cb_type = callback[:type]
      var = model_name.underscore

      <<~MINITEST
        test "executes #{cb_type} callback" do
          #{var} = #{model_name}.new
          assert_respond_to #{var}, :valid?
        end
      MINITEST
    end

    def generate_minitest_custom_methods(suggestion)
      model_name = suggestion[:model]
      methods = suggestion[:custom_methods] || []

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          #{methods.map { |m| minitest_custom_method_test(m, model_name) }.join("\n")}
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def minitest_custom_method_test(method, model_name)
      name = method.is_a?(Hash) ? method[:name] : method.to_sym
      is_class_method = method.is_a?(Hash) && method[:class_method]
      var = model_name.underscore

      if is_class_method
        <<~MINITEST
          test ".#{name} returns a result" do
            assert_respond_to #{model_name}, :#{name}
          end
        MINITEST
      else
        <<~MINITEST
          test "##{name} returns a result" do
            #{var} = #{model_name}.new
            assert_respond_to #{var}, :#{name}
          end
        MINITEST
      end
    end

    def generate_minitest_factories(suggestion)
      model_name = suggestion[:model]
      var = model_name.underscore

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          test "valid factory" do
            #{var} = #{model_name}.new
            assert #{var}.valid?
          end
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def generate_minitest_serialization(suggestion)
      model_name = suggestion[:model]
      var = model_name.underscore

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{model_name}Test < ActiveSupport::TestCase
          test "serializes to_json" do
            #{var} = #{model_name}.new
            assert_respond_to #{var}, :to_json
          end
        end
      MINITEST

      write_test_file(model_name, test_content)
    end

    def generate_minitest_request_test(suggestion)
      controller_name = suggestion[:controller]
      ctrl = controller_name.to_s.sub(/Controller$/, "").underscore
      table = ctrl.pluralize

      test_content = <<~MINITEST
        # frozen_string_literal: true

        require "test_helper"

        class #{controller_name}Test < ActionDispatch::IntegrationTest
          test "should get index" do
            get #{table}_url
            assert_response :success
          end
        end
      MINITEST

      write_test_file("#{ctrl}_controller", test_content)
    end

  end
end
