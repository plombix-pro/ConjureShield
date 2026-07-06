require "fileutils"

module Conjureshield
  class TestGenerator
    attr_reader :code, :suggestions, :templates

    def initialize(code, suggestions)
      @code = code
      @suggestions = suggestions
      @templates = Templates.load
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

    def generate_all
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
          @_devise_model = File.basename(model[:path], ".rb").split("_").map(&:capitalize).join
          break
        end
      end
      @_devise_model || "User"
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
      name.to_s.sub(/Controller$/, "").underscore.singularize
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

    def minitest?
      @framework == :minitest
    end

    def generate_stimulus_test(suggestion)
      controller = suggestion[:controller]

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller}", type: :stimulus do
          describe "Stimulus controller" do
            it "initializes with correct defaults" do
              expect(controller).to receive(:value).and_call_original
              controller.initialize
            end

            it "handles value changes" do
              controller = StimulusController.new
              expect(controller.value).to eq("default")
            end

            it "triggers action on value change" do
              controller = StimulusController.new
              expect(controller).to receive(:value_changed)
              controller.value = "new_value"
            end

            it "triggers action on target change" do
              controller = StimulusController.new
              expect(controller).to receive(:target_changed)
              controller.target = "new_target"
            end
          end
        end
      TEST

      write_test_file(controller, test_content)
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

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "validations" do
            #{generate_validation_contexts(fields, validations)}
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_validation_contexts(fields, validations)
      contexts = []

      validations.each do |validation|
        contexts << generate_validation_context(validation)
      end

      contexts.join("\n")
    end

    def generate_validation_context(validation)
      field = validation[:field]
      validators = validation[:validators] || []

      matchers = validators.map do |v|
        case v.to_s.downcase
        when "presence"
          "it { is_expected.to validate_presence_of(:#{field}) }"
        when "uniqueness"
          "it { is_expected.to validate_uniqueness_of(:#{field}) }"
        when "length"
          "it { is_expected.to validate_length_of(:#{field}) }"
        when "inclusion"
          "it { is_expected.to validate_inclusion_of(:#{field}).in_array([]) }"
        when "format"
          "it { is_expected.to allow_value(\"value\").for(:#{field}) }"
        when "numericality"
          "it { is_expected.to validate_numericality_of(:#{field}) }"
        else
          "it { is_expected.to validate_presence_of(:#{field}) }"
        end
      end

      <<-CONTEXT
            context "validates #{field}" do
              #{matchers.join("\n              ")}
            end
      CONTEXT
    end

    def generate_validation_messages_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "validation error messages" do
            it "returns custom error messages" do
              expect(build(:#{model[:model].downcase}), invalid_data: "value").errors.full_messages
            end

            it "returns I18n localized messages" do
              expect(build(:#{model[:model].downcase}), invalid_data: "value").errors.full_messages
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_has_one_test(model)
      associations = model[:associations].select { |a| a[:type] == :has_one }

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "associations" do
            context "has_one associations" do
              #{associations.map { |assoc| generate_has_one_context(assoc) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_has_one_context(assoc)
      target = assoc[:target]

      <<-CONTEXT
              it { is_expected.to have_one(:#{target.downcase}) }
              it { is_expected.to have_one(:#{target.downcase}) }
      CONTEXT
    end

    def generate_has_many_test(model)
      associations = model[:associations].select { |a| a[:type] == :has_many }

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "associations" do
            context "has_many associations" do
              #{associations.map { |assoc| generate_has_many_context(assoc) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_has_many_context(assoc)
      target = assoc[:target]

      <<-CONTEXT
              it { is_expected.to have_many(:#{target.downcase.pluralize}) }
              it { is_expected.to have_many(:#{target.downcase.pluralize}) }
      CONTEXT
    end

    def generate_belongs_to_test(model)
      associations = model[:associations].select { |a| a[:type] == :belongs_to }

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "associations" do
            context "belongs_to associations" do
              #{associations.map { |assoc| generate_belongs_to_context(assoc) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_belongs_to_context(assoc)
      target = assoc[:target]

      <<-CONTEXT
              it { is_expected.to belong_to(:#{target.downcase}) }
              it { is_expected.to belong_to(:#{target.downcase}) }
      CONTEXT
    end

    def generate_association_validations_test(model)
      associations = model[:associations]

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "associations" do
            context "association validations" do
              it { is_expected.to validate_associated_#{model[:model].downcase.pluralize}_of(:#{model[:model].downcase}) }
              it { is_expected.to validate_associated_#{model[:model].downcase.pluralize}_of(:#{model[:model].downcase}).on(:create) }
              it { is_expected.to validate_associated_#{model[:model].downcase.pluralize}_of(:#{model[:model].downcase}).on(:update) }
              it { is_expected.to validate_associated_#{model[:model].downcase.pluralize}_of(:#{model[:model].downcase}).case_insensitive }
              it { is_expected.to validate_associated_#{model[:model].downcase.pluralize}_of(:#{model[:model].downcase}).with_message("custom message") }
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_scopes_test(model)
      scopes = model[:scopes]
      model_name = model[:model]
      columns = model[:columns] || {}

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "scopes" do
            #{scopes.map { |scope| generate_scope_test(scope, model_name, columns: columns) }.join("\n")}
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_scope_test(scope, model_name, columns: {})
      name = scope[:name]
      args = scope[:args]

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

      <<-TEST
            it "returns #{name} results" do
              record = described_class.create!(#{attrs_str})
              expect(described_class.#{name}).to be_present
            end
      TEST
    end

    def generate_scoped_arguments_test(model)
      scopes = model[:scopes]
      model_name = model[:model]

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "scopes with arguments" do
            #{scopes.map { |scope| generate_scoped_arguments_context(scope, model_name) }.join("\n")}
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_scoped_arguments_context(scope, model_name)
      name = scope[:name]
      args = scope[:args]

      <<-CONTEXT
            it "accepts #{name} with #{args.join(", ")}" do
              expect(described_class.#{name}(#{args.join(", ")})).to be_present
            end
      CONTEXT
    end

    def generate_before_save_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :before_save }
      model_name = model[:model]
      columns = model[:columns] || {}

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "callbacks" do
            context "before_save callbacks" do
              #{callbacks.map { |cb| generate_before_save_context(cb, model_name, columns: columns) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_before_save_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      <<-CONTEXT
              it "executes before_save callback" do
                #{var} = described_class.new(#{attrs_str})
                expect { #{var}.save(validate: false) }.not_to raise_error
              end
      CONTEXT
    end

    def generate_after_save_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :after_save }
      model_name = model[:model]
      columns = model[:columns] || {}

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "callbacks" do
            context "after_save callbacks" do
              #{callbacks.map { |cb| generate_after_save_context(cb, model_name, columns: columns) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_after_save_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      <<-CONTEXT
              it "executes after_save callback" do
                #{var} = described_class.new(#{attrs_str})
                expect { #{var}.save }.not_to raise_error
              end
      CONTEXT
    end

    def generate_before_destroy_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :before_destroy }
      model_name = model[:model]
      columns = model[:columns] || {}

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "callbacks" do
            context "before_destroy callbacks" do
              #{callbacks.map { |cb| generate_before_destroy_context(cb, model_name, columns: columns) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_before_destroy_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      <<-CONTEXT
              it "executes before_destroy callback" do
                #{var} = described_class.new(#{attrs_str})
                expect { #{var}.destroy }.not_to raise_error
              end
      CONTEXT
    end

    def generate_after_destroy_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :after_destroy }
      model_name = model[:model]
      columns = model[:columns] || {}

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "callbacks" do
            context "after_destroy callbacks" do
              #{callbacks.map { |cb| generate_after_destroy_context(cb, model_name, columns: columns) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_after_destroy_context(callback, model_name, columns: {})
      var = model_name.underscore
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      <<-CONTEXT
              it "executes after_destroy callback" do
                #{var} = described_class.new(#{attrs_str})
                expect { #{var}.destroy }.not_to raise_error
              end
      CONTEXT
    end

    def generate_custom_methods_test(model)
      methods = model[:custom_methods]
      model_name = model[:model]
      columns = model[:columns] || {}

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model_name}, type: :model do
          describe "custom methods" do
            #{methods.map { |m| generate_custom_method_test(m, model_name, columns: columns) }.join("\n")}
          end
        end
      TEST

      write_test_file(model_name, test_content)
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

      <<-TEST
            it "returns #{name} result" do
              expect(#{receiver}.#{name}).to #{matcher}
            end
      TEST
    end

    def generate_factories_test(model)
      model_name = model[:model]
      columns = model[:columns] || {}
      attrs = factory_attributes(model_name, columns: columns)
      attrs_str = attrs.map { |k, v| "#{k}: #{v.inspect}" }.join(",\n        ")

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

         RSpec.describe #{model_name} do
          it "creates valid #{model_name.downcase} instances" do
            record = #{model_name}.new(
              #{attrs_str}
            )
            expect(record).to be_valid
          end

          it "creates #{model_name.downcase} with default values" do
            record = #{model_name}.new(
              #{attrs_str}
            )
            expect(record).to be_valid
          end
        end
      TEST

      write_test_file(model_name, test_content)
    end

    def generate_serialization_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe #{model[:model]}, type: :model do
          describe "serialization" do
            it "serializes to JSON" do
              expect(build(:#{model[:model].downcase}).to_json).to be_present
            end

            it "serializes to YAML" do
              expect(build(:#{model[:model].downcase}).to_yaml).to be_present
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
              expect(build(:#{model[:model].downcase})).to delegate(:method_name).to(:association_name)
            end

            it "delegates method with prefix" do
              expect(build(:#{model[:model].downcase})).to delegate(:method_name).to(:association_name, prefix: true)
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_get_index_test(controller)
      devise_block = devise_setup
      route_plural = ctrl_route(controller[:controller])
      model_name = controller[:model]
      columns = controller[:columns] || {}

      attrs1 = factory_attributes(model_name, columns: columns)
      attrs2 = factory_attributes(model_name, columns: columns)
      attrs1_str = attrs1.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
      attrs2_str = attrs2.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          #{devise_block}
          describe "GET index action" do
            let!(:record1) { #{model_name}.create!(#{attrs1_str}) }
            let!(:record2) { #{model_name}.create!(#{attrs2_str}) }

            it "returns success response" do
              get #{route_plural}_path
              expect(response).to have_http_status(:ok)
            end

            it "renders index template" do
              get #{route_plural}_path
              expect(response).to render_template(:index)
            end

            it "passes correct instance variables" do
              get #{route_plural}_path
              expect(assigns(:#{route_plural})).to be_present
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
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
                get "#{controller[:controller].downcase.pluralize}s_path?page=2"
                expect(assigns(:page)).to eq(2)
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
                get "#{controller[:controller].downcase.pluralize}s_path?sort=field"
                expect(assigns(:sort)).to eq("field")
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

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}", type: :request do
          #{devise_setup}
          describe "GET show action" do
            let!(:record) { #{model_name}.create!(#{attrs_str}) }

            it "returns success response" do
              get #{singular}_path(#{show_path_arg})
              expect(response).to have_http_status(:ok)
            end

            it "renders show template" do
              get #{singular}_path(#{show_path_arg})
              expect(response).to render_template(:show)
            end

            it "passes correct instance variables" do
              get #{singular}_path(#{show_path_arg})
              expect(assigns(:#{singular})).to be_present
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
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
              get new_#{ctrl_route(controller[:controller])}_path
              expect(response).to have_http_status(:ok)
            end

            it "renders new template" do
              get "#{controller[:controller].downcase.pluralize}_new"
              expect(response).to render_template(:new)
            end

            it "passes correct instance variables" do
              get "#{controller[:controller].downcase.pluralize}_new"
              expect(assigns(:#{ctrl_base(controller[:controller])})).to be_a(#{controller[:controller]})
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
                get "#{controller[:controller].downcase.pluralize}_new"
                expect(response).to render_template(:new)
              end

              it "includes all form fields" do
                get "#{controller[:controller].downcase.pluralize}_new"
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
              get edit_#{ctrl_route(controller[:controller])}_path(1)
              expect(response).to have_http_status(:ok)
            end

            it "renders edit template" do
              get "#{controller[:controller].downcase.pluralize}_edit/#{controller[:controller].downcase}_id"
              expect(response).to render_template(:edit)
            end

            it "passes correct instance variables" do
              get "#{controller[:controller].downcase.pluralize}_edit/#{controller[:controller].downcase}_id"
              expect(assigns(:#{controller[:controller].downcase})).to be_a(#{controller[:controller].downcase})
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
                get "#{controller[:controller].downcase.pluralize}_edit/#{controller[:controller].downcase}_id"
                expect(response).to render_template(:edit)
              end

              it "includes pre-filled form fields" do
                get "#{controller[:controller].downcase.pluralize}_edit/#{controller[:controller].downcase}_id"
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
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(response).to have_http_status(:created)
              end

              it "redirects to new record" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{ctrl_base(controller[:controller])}": {
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{ctrl_route(controller[:controller])}_path)
              end

              it "assigns correct instance variables" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(assigns(:#{controller[:controller].downcase})).to be_a(#{controller[:controller].downcase})
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_create_params(controller_name)
      "id: 1, #{ctrl_base(controller_name)}: { name: \"Test\" }"
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
                  "#{controller[:controller].downcase}": {
                    invalid_field: "value"
                  }
                }
                expect(response).to have_http_status(:unprocessable_entity)
              end

              it "renders new template with errors" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{controller[:controller].downcase}": {
                    invalid_field: "value"
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
                  "#{controller[:controller].downcase}": {
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "sets flash messages" do
                post #{ctrl_route(controller[:controller])}_path, params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_create_params(controller[:controller])}
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
                put #{ctrl_route(controller[:controller])}_path(1), params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(response).to have_http_status(:ok)
              end

              it "redirects to updated record" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "updates the record in database" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(#{ctrl_route(controller[:controller])}.find_by(id: 1).#{ctrl_base(controller_name)}).to eq("updated")
              end
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_update_params(controller_name)
      "id: 1, #{controller_name.downcase}: { name: \"Updated\" }"
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
                  "#{controller[:controller].downcase}": {
                    invalid_field: "value"
                  }
                }
                expect(response).to have_http_status(:unprocessable_entity)
              end

              it "renders edit template with errors" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{controller[:controller].downcase}": {
                    invalid_field: "value"
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
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "sets flash messages" do
                put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
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
              delete #{ctrl_route(controller[:controller])}_path(1)
              expect(response).to have_http_status(:no_content)
            end

            it "removes the record from database" do
              delete #{ctrl_base(controller[:controller]).singularize}_path(1)
              expect(#{controller[:controller].downcase.pluralize}.find_by(id: 1)).to be_nil
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
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
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
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}Parameters", type: :request do
          describe "strong parameters" do
            it "allows permitted attributes" do
              expect(controller_params).to permit(
                #{controller[:controller].downcase}: {
                  #{generate_permit_attrs(controller[:controller])}
                }
              )
            end

            it "allows nested attributes" do
              expect(controller_params).to permit(
                #{controller[:controller].downcase}: {
                  #{controller[:controller].downcase.pluralize}: {
                    association_id: 1
                  }
                }
              )
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_permit_attrs(controller_name)
      "name: \"Test\", #{controller_name.downcase}: { email: \"test@example.com\" }"
    end

    def generate_strong_parameters_deny_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

        RSpec.describe "#{controller[:controller]}Parameters", type: :request do
          describe "strong parameters" do
            it "denies non-permitted attributes" do
              expect(controller_params).not_to permit(
                #{controller[:controller].downcase}: {
                  admin: true
                }
              )
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
                "#{controller[:controller].downcase}": {
                  #{generate_create_params(controller[:controller])}
                }
              }
              expect(flash[:notice]).to be_present
            end

            it "sets alert flash" do
              post #{ctrl_route(controller[:controller])}_path, params: {
                "#{controller[:controller].downcase}": {
                  invalid_field: "value"
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
                "#{controller[:controller].downcase}": {
                  #{generate_create_params(controller[:controller])}
                }
              }
              expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
            end

            it "redirects to edit record" do
              put #{ctrl_base(controller[:controller]).singularize}_path(1), params: {
                "#{controller[:controller].downcase}": {
                  #{generate_update_params(controller[:controller])}
                }
              }
              expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
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
                "#{controller[:controller].downcase}": {
                  #{generate_create_params(controller[:controller])}
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

      test_content = <<~TEST
        # frozen_string_literal: true

        #{spec_helper_require}

         RSpec.describe "#{ctrl_base(controller).capitalize}", type: :request do
          #{devise_setup}
          describe "user workflow" do
            context "create and view" do
              it "creates a new #{model} and redirects to show" do
                post #{ctrl_route(controller)}_path, params: {
                  "#{ctrl_base(controller)}": {
                    id: 1, #{ctrl_base(controller)}: { name: "Test" }
                  }
                }
                expect(response).to redirect_to(#{ctrl_route(controller)}_path)
                expect(flash[:notice]).to be_present
              end

              it "displays the created #{model} with all attributes" do
                post #{ctrl_route(controller)}_path, params: {
                  "#{ctrl_base(controller)}": {
                    id: 1, #{ctrl_base(controller)}: { name: "Test" }
                  }
                }
                follow_redirect!
                expect(response).to have_http_status(:ok)
                expect(page).to have_content(/#{model}/i)
              end
            end

            context "edit and update" do
              it "edits the #{model} and saves changes" do
                put #{ctrl_route(controller)}_path(1), params: {
                  "#{ctrl_base(controller)}": {
                    id: 1, #{ctrl_base(controller)}: { name: "Updated" }
                  }
                }
                expect(response).to redirect_to(#{ctrl_base(controller)}_path)
                expect(flash[:notice]).to be_present
              end

              it "displays the updated #{model} with new values" do
                put #{ctrl_base(controller).singularize}_path(1), params: {
                  "#{ctrl_base(controller)}": {
                    id: 1, #{ctrl_base(controller)}: { name: "Updated" }
                  }
                }
                follow_redirect!
                expect(response).to have_http_status(:ok)
                expect(page).to have_content(/Updated/i)
              end
            end

            context "delete" do
              it "deletes the #{model} and redirects to index" do
                delete #{ctrl_route(controller)}_path(1)
                expect(response).to redirect_to(#{ctrl_base(controller)}_path)
                expect(flash[:notice]).to be_present
              end

              it "removes the #{model} from the list" do
                visit #{ctrl_route(controller)}_path
                within(first(%(a[href*="/#{ctrl_route(controller)}/1"]))) do
                  click_link("Delete")
                end
                expect(page).to have_content("#{model} was successfully deleted.")
                expect(page).not_to have_link("1")
              end
            end
          end
        end
      TEST

      write_test_file("#{controller}_integration", test_content)
    end

    def write_test_file(subject, content)
      base = @codebase_path || Dir.pwd
      base_dir = File.join(base, rspec? ? "spec" : "test")
      FileUtils.mkdir_p(base_dir)
      ext = rspec? ? "_spec.rb" : "_test.rb"
      basename = subject.to_s.underscore
      suffix = @current_type
      test_path = File.join(base_dir, "#{basename}_#{suffix}#{ext}")

      File.write(test_path, content)
      puts "Generated test: #{test_path}"
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
                         invalid_field: "value"
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
          let(:#{model.downcase}) { create(:#{model.downcase}) }

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

      <<-MINITEST
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

      <<-MINITEST
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

      <<-MINITEST
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

      <<-MINITEST
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
      var = model_name.underscore

      <<-MINITEST
          test "##{method} returns a result" do
            #{var} = #{model_name}.new
            assert_respond_to #{var}, :#{method}
          end
      MINITEST
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
