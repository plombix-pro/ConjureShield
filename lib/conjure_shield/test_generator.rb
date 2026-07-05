module Conjureshield
  class TestGenerator
    attr_reader :code, :suggestions, :templates

    def initialize(code, suggestions)
      @code = code
      @suggestions = suggestions
      @templates = Templates.load
    end

    def self.generate(code, suggestions)
      new(code, suggestions).generate_all
    end

    def generate_all
      suggestions.each do |suggestion|
        generate_test(suggestion)
      end
    end

    def generate_test(suggestion)
      case suggestion[:type]
      when :validations
        generate_validations_test(suggestion)
      when :validation_messages
        generate_validation_messages_test(suggestion)
      when :has_one
        generate_has_one_test(suggestion)
      when :has_many
        generate_has_many_test(suggestion)
      when :belongs_to
        generate_belongs_to_test(suggestion)
      when :association_validations
        generate_association_validations_test(suggestion)
      when :scopes
        generate_scopes_test(suggestion)
      when :scoped_arguments
        generate_scoped_arguments_test(suggestion)
      when :before_save
        generate_before_save_test(suggestion)
      when :after_save
        generate_after_save_test(suggestion)
      when :before_destroy
        generate_before_destroy_test(suggestion)
      when :after_destroy
        generate_after_destroy_test(suggestion)
      when :custom_methods
        generate_custom_methods_test(suggestion)
      when :factories
        generate_factories_test(suggestion)
      when :serialization
        generate_serialization_test(suggestion)
      when :delegation
        generate_delegation_test(suggestion)
      when :get_index
        generate_get_index_test(suggestion)
      when :index_pagination
        generate_index_pagination_test(suggestion)
      when :index_sorting
        generate_index_sorting_test(suggestion)
      when :get_show
        generate_get_show_test(suggestion)
      when :show_with_associations
        generate_show_with_associations_test(suggestion)
      when :get_new
        generate_get_new_test(suggestion)
      when :new_form
        generate_new_form_test(suggestion)
      when :get_edit
        generate_get_edit_test(suggestion)
      when :edit_form
        generate_edit_form_test(suggestion)
      when :post_create_valid
        generate_post_create_valid_test(suggestion)
      when :post_create_invalid
        generate_post_create_invalid_test(suggestion)
      when :post_create_redirect
        generate_post_create_redirect_test(suggestion)
      when :put_patch_update_valid
        generate_put_patch_update_valid_test(suggestion)
      when :put_patch_update_invalid
        generate_put_patch_update_invalid_test(suggestion)
      when :put_patch_update_redirect
        generate_put_patch_update_redirect_test(suggestion)
      when :delete_destroy
        generate_delete_destroy_test(suggestion)
      when :delete_destroy_redirect
        generate_delete_destroy_redirect_test(suggestion)
      when :strong_parameters_permit
        generate_strong_parameters_permit_test(suggestion)
      when :strong_parameters_deny
        generate_strong_parameters_deny_test(suggestion)
      when :flash_messages
        generate_flash_messages_test(suggestion)
      when :redirects
        generate_redirects_test(suggestion)
      when :json_responses
        generate_json_responses_test(suggestion)
      when :create_view
        generate_integration_test(suggestion)
      when :edit_update
        generate_integration_test(suggestion)
      when :delete
        generate_integration_test(suggestion)
      when :view_details
        generate_integration_test(suggestion)
      when :get_list
        generate_api_test(suggestion)
      when :get_single
        generate_api_test(suggestion)
      when :post_create
        generate_api_test(suggestion)
      when :put_update
        generate_api_test(suggestion)
      when :delete_destroy
        generate_api_test(suggestion)
      when :create_view_feature
        generate_feature_test(suggestion)
      when :edit_feature
        generate_feature_test(suggestion)
      when :delete_feature
        generate_feature_test(suggestion)
      when :view_details_feature
        generate_feature_test(suggestion)
      when :stimulus
        generate_stimulus_test(suggestion)
      when :cable
        generate_cable_test(suggestion)
      end
    end

    private

    def generate_stimulus_test(suggestion)
      controller = suggestion[:controller]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

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

      write_test_file("#{controller}_stimulus", test_content)
    end

    def generate_cable_test(suggestion)
      channel = suggestion[:channel]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

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

      write_test_file("#{channel}_cable", test_content)
    end

    def generate_validations_test(model)
      fields = model[:fields]
      validations = model[:validations]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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
      validator = validation[:validator]

      <<-CONTEXT
            context "validates #{field}" do
              it { is_expected.to validate_presence_of(:#{field}) }
              it { is_expected.to validate_inclusion_of(:#{field}).in_array([valid_value]).allow_nil }
              it { is_expected.to validate_uniqueness_of(:#{field}).on(:create).case_insensitive }
              it { is_expected.to validate_format_of(:#{field}).with(:email) }
            end
      CONTEXT
    end

    def generate_validation_messages_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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
              it { is_expected.to have_1_#{target.downcase.pluralize}_association }
              it { is_expected.to have_1_#{target.downcase}_association }
              it { is_expected.to have_1_#{target.downcase}_association.that.exists }
              it { is_expected.to have_1_#{target.downcase}_association.that.is_a(#{target}) }
              it { is_expected.to have_1_#{target.downcase}_association.that.is_a(#{target}) }
            end
      CONTEXT
    end

    def generate_has_many_test(model)
      associations = model[:associations].select { |a| a[:type] == :has_many }

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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
              it { is_expected.to have_many_#{target.downcase.pluralize}_associations }
              it { is_expected.to have_many_#{target.downcase.pluralize}_associations.that.exists }
              it { is_expected.to have_many_#{target.downcase.pluralize}_associations.that.are_a(#{target}) }
              it { is_expected.to have_many_#{target.downcase.pluralize}_associations.that.are_a(#{target}) }
            end
      CONTEXT
    end

    def generate_belongs_to_test(model)
      associations = model[:associations].select { |a| a[:type] == :belongs_to }

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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
              it { is_expected.to belong_to_#{target.downcase}_associations }
              it { is_expected.to belong_to_#{target.downcase}_associations.that.exists }
              it { is_expected.to belong_to_#{target.downcase}_associations.that.is_a(#{target}) }
              it { is_expected.to belong_to_#{target.downcase}_associations.that.is_a(#{target}) }
            end
      CONTEXT
    end

    def generate_association_validations_test(model)
      associations = model[:associations]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "scopes" do
            #{scopes.map { |scope| generate_scope_test(scope) }.join("\n")}
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_scope_test(scope)
      name = scope[:name]
      args = scope[:args]

      <<-TEST
            it "returns #{name} results" do
              expect(#{model[:model].downcase.pluralize}.#{name}).to be_present
            end

            it "returns #{name} results with arguments" do
              expect(#{model[:model].downcase.pluralize}.#{name}(#{args.join(", ")})).to be_present
            end
      TEST
    end

    def generate_scoped_arguments_test(model)
      scopes = model[:scopes]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "scopes with arguments" do
            #{scopes.map { |scope| generate_scoped_arguments_context(scope) }.join("\n")}
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_scoped_arguments_context(scope)
      name = scope[:name]
      args = scope[:args]

      <<-CONTEXT
            it "accepts #{name} with #{args.join(", ")}" do
              expect(#{model[:model].downcase.pluralize}.#{name}(#{args.join(", ")})).to be_present
            end
      CONTEXT
    end

    def generate_before_save_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :before_save }

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "callbacks" do
            context "before_save callbacks" do
              #{callbacks.map { |callback| generate_before_save_context(callback) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_before_save_context(callback)
      <<-CONTEXT
              it "executes before_save callback" do
                expect {
                  build(:#{model[:model].downcase})
                }.to change { model[:model].downcase }.from(nil).to(be_present)
              end
      CONTEXT
    end

    def generate_after_save_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :after_save }

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "callbacks" do
            context "after_save callbacks" do
              #{callbacks.map { |callback| generate_after_save_context(callback) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_after_save_context(callback)
      <<-CONTEXT
              it "executes after_save callback" do
                expect {
                  create(:#{model[:model].downcase})
                }.to change { model[:model].downcase }.from(nil).to(be_present)
              end
      CONTEXT
    end

    def generate_before_destroy_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :before_destroy }

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "callbacks" do
            context "before_destroy callbacks" do
              #{callbacks.map { |callback| generate_before_destroy_context(callback) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_before_destroy_context(callback)
      <<-CONTEXT
              it "executes before_destroy callback" do
                expect {
                  destroy(:#{model[:model].downcase})
                }.to change { model[:model].downcase }.from(be_present).to(nil)
              end
      CONTEXT
    end

    def generate_after_destroy_test(model)
      callbacks = model[:callbacks].select { |c| c[:type] == :after_destroy }

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "callbacks" do
            context "after_destroy callbacks" do
              #{callbacks.map { |callback| generate_after_destroy_context(callback) }.join("\n")}
            end
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_after_destroy_context(callback)
      <<-CONTEXT
              it "executes after_destroy callback" do
                expect {
                  destroy(:#{model[:model].downcase})
                }.to change { model[:model].downcase }.from(be_present).to(nil)
              end
      CONTEXT
    end

    def generate_custom_methods_test(model)
      methods = model[:custom_methods]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
          describe "custom methods" do
            #{methods.map { |method| generate_custom_method_test(method) }.join("\n")}
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_custom_method_test(method)
      <<-TEST
            it "returns #{method} result" do
              expect(build(:#{model[:model].downcase}).#{method}).to be_present
            end
      TEST
    end

    def generate_factories_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "FactoryBot factories for #{model[:model]}" do
          it "creates valid #{model[:model].downcase} instances" do
            factory = FactoryBot.build(:#{model[:model].downcase})
            expect(factory).to be_valid
          end

          it "creates #{model[:model].downcase} with default values" do
            factory = FactoryBot.build(:#{model[:model].downcase})
            expect(factory).to have_attributes(default_attributes)
          end

          it "creates #{model[:model].downcase} with custom values" do
            factory = FactoryBot.build(:#{model[:model].downcase}, custom_attrs: "value")
            expect(factory).to have_attributes(custom_attrs: "value")
          end
        end
      TEST

      write_test_file(model[:model], test_content)
    end

    def generate_serialization_test(model)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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

        require "rails_helper"

        RSpec.describe "#{model[:model]}", type: :model do
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
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET index action" do
            it "returns success response" do
              get "#{controller[:controller].downcase.pluralize}s_path"
              expect(response).to have_http_status(:ok)
            end

            it "renders index template" do
              get "#{controller[:controller].downcase.pluralize}s_path"
              expect(response).to render_template(:index)
            end

            it "passes correct instance variables" do
              get "#{controller[:controller].downcase.pluralize}s_path"
              expect(assigns(:#{controller[:controller].downcase.pluralize})).to be_present
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_index_pagination_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET index action" do
            context "with pagination" do
              it "returns paginated results" do
                get "#{controller[:controller].downcase.pluralize}s_path"
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET index action" do
            context "with sorting" do
              it "sorts by default" do
                get "#{controller[:controller].downcase.pluralize}s_path"
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
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET show action" do
            it "returns success response" do
              get "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
              expect(response).to have_http_status(:ok)
            end

            it "renders show template" do
              get "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
              expect(response).to render_template(:show)
            end

            it "passes correct instance variables" do
              get "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
              expect(assigns(:#{controller[:controller].downcase})).to be_present
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_show_with_associations_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET show action" do
            context "with associations" do
              it "includes associated records" do
                get "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET new action" do
            it "returns success response" do
              get "#{controller[:controller].downcase.pluralize}_new"
              expect(response).to have_http_status(:ok)
            end

            it "renders new template" do
              get "#{controller[:controller].downcase.pluralize}_new"
              expect(response).to render_template(:new)
            end

            it "passes correct instance variables" do
              get "#{controller[:controller].downcase.pluralize}_new"
              expect(assigns(:#{controller[:controller].downcase})).to be_a(#{controller[:controller].downcase})
            end
          end
        end
      TEST

      write_test_file(controller[:controller], test_content)
    end

    def generate_new_form_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "GET edit action" do
            it "returns success response" do
              get "#{controller[:controller].downcase.pluralize}_edit/#{controller[:controller].downcase}_id"
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

        require "rails_helper"

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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "POST create action" do
            context "with valid parameters" do
              it "creates new record" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(response).to have_http_status(:created)
              end

              it "redirects to new record" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "assigns correct instance variables" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
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
      "id: 1, #{controller_name.downcase}: { name: \"Test\" }"
    end

    def generate_post_create_invalid_test(controller)
      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "POST create action" do
            context "with invalid parameters" do
              it "returns validation errors" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
                  "#{controller[:controller].downcase}": {
                    invalid_field: "value"
                  }
                }
                expect(response).to have_http_status(:unprocessable_entity)
              end

              it "renders new template with errors" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "POST create action" do
            context "with redirect" do
              it "redirects to new record" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_create_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "sets flash messages" do
                post "#{controller[:controller].downcase.pluralize}s_path", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "PUT/PATCH update action" do
            context "with valid parameters" do
              it "updates the record" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(response).to have_http_status(:ok)
              end

              it "redirects to updated record" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "updates the record in database" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(#{controller[:controller].downcase.pluralize}.find_by(id: 1).#{controller_name.downcase}).to eq("updated")
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "PUT/PATCH update action" do
            context "with invalid parameters" do
              it "returns validation errors" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
                  "#{controller[:controller].downcase}": {
                    invalid_field: "value"
                  }
                }
                expect(response).to have_http_status(:unprocessable_entity)
              end

              it "renders edit template with errors" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "PUT/PATCH update action" do
            context "with redirect" do
              it "redirects to updated record" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
                  "#{controller[:controller].downcase}": {
                    #{generate_update_params(controller[:controller])}
                  }
                }
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "sets flash messages" do
                put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "DELETE destroy action" do
            it "deletes the record" do
              delete "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
              expect(response).to have_http_status(:no_content)
            end

            it "removes the record from database" do
              delete "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "DELETE destroy action" do
            context "with redirect" do
              it "redirects after destroy" do
                delete "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
                expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
              end

              it "sets flash messages" do
                delete "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id"
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

        require "rails_helper"

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

        require "rails_helper"

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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "flash messages" do
            it "sets notice flash" do
              post "#{controller[:controller].downcase.pluralize}s_path", params: {
                "#{controller[:controller].downcase}": {
                  #{generate_create_params(controller[:controller])}
                }
              }
              expect(flash[:notice]).to be_present
            end

            it "sets alert flash" do
              post "#{controller[:controller].downcase.pluralize}s_path", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "redirects" do
            it "redirects to new record" do
              post "#{controller[:controller].downcase.pluralize}s_path", params: {
                "#{controller[:controller].downcase}": {
                  #{generate_create_params(controller[:controller])}
                }
              }
              expect(response).to redirect_to(#{controller[:controller].downcase.pluralize}_path)
            end

            it "redirects to edit record" do
              put "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller[:controller]}", type: :request do
          describe "JSON responses" do
            it "returns JSON for show action" do
              get "#{controller[:controller].downcase.pluralize}_path/#{controller[:controller].downcase}_id", headers: { "Accept" => "application/json" }
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body).to be_a(Hash)
            end

            it "returns JSON for create action" do
              post "#{controller[:controller].downcase.pluralize}s_path", params: {
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

        require "rails_helper"

        RSpec.describe "#{controller}/#{controller}", type: :integration do
          describe "user workflow" do
            context "create and view" do
              it "creates a new #{model} and redirects to show" do
                post "#{controller}s_path", params: {
                  "#{controller.downcase}": {
                    id: 1, #{controller.downcase}: { name: "Test" }
                  }
                }
                expect(response).to redirect_to(#{model.pluralize}_path)
                expect(flash[:notice]).to eq("#{model} was successfully created.")
              end

              it "displays the created #{model} with all attributes" do
                post "#{controller}s_path", params: {
                  "#{controller.downcase}": {
                    id: 1, #{controller.downcase}: { name: "Test" }
                  }
                }
                follow_redirect!
                expect(response).to have_http_status(:ok)
                expect(page).to have_content("Show #{model}")
              end
            end

            context "edit and update" do
              it "edits the #{model} and saves changes" do
                put "#{controller}_path/1", params: {
                  "#{controller.downcase}": {
                    id: 1, #{controller.downcase}: { name: "Updated" }
                  }
                }
                expect(response).to redirect_to(#{model.pluralize}_path)
                expect(flash[:notice]).to eq("#{model} was successfully updated.")
              end

              it "displays the updated #{model} with new values" do
                put "#{controller}_path/1", params: {
                  "#{controller.downcase}": {
                    id: 1, #{controller.downcase}: { name: "Updated" }
                  }
                }
                follow_redirect!
                expect(response).to have_http_status(:ok)
                expect(page).to have_content("Updated #{model}")
              end
            end

            context "delete" do
              it "deletes the #{model} and redirects to index" do
                delete "#{controller}_path/1"
                expect(response).to redirect_to(#{model.pluralize}_path)
                expect(flash[:notice]).to eq("#{model} was successfully deleted.")
              end

              it "removes the #{model} from the list" do
                visit "#{controller}s_path"
                within(first("a[href*='/#{controller}s_path/1']")) do
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

    def generate_api_test(suggestion)
      controller = suggestion[:controller]
      model = suggestion[:model]

      test_content = <<~TEST
        # frozen_string_literal: true

        require "rails_helper"

        RSpec.describe "#{controller}/#{controller}", type: :api do
          describe "GET #{controller.pluralize}" do
            it "returns 200 and list of #{model.pluralize}s" do
              get "#{controller.pluralize}s_path"
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body).to be_a(Array)
              expect(response.parsed_body).to all(be_a(#{model.downcase}))
            end

            it "returns 401 when not authenticated" do
              get "#{controller.pluralize}s_path"
              expect(response).to have_http_status(:unauthorized)
            end
          end

          describe "POST #{controller.pluralize}s" do
            context "with valid payload" do
              it "creates a new #{model} and returns 201" do
                post "#{controller.pluralize}s_path",
                     params: {
                       "#{controller.downcase}": {
                         id: 1, #{controller.downcase}: { name: "Test" }
                       }
                     },
                     headers: { "Authorization" => "Bearer #{access_token}" }
                expect(response).to have_http_status(:created)
                expect(response.parsed_body[:id]).to be_present
                expect(response.parsed_body[:#{controller.downcase}]).to be_a(Hash)
              end
            end

            context "with invalid payload" do
              it "returns 422 with validation errors" do
                post "#{controller.pluralize}s_path",
                     params: {
                       "#{controller.downcase}": {
                         invalid_field: "value"
                       }
                     },
                     headers: { "Authorization" => "Bearer #{access_token}" }
                expect(response).to have_http_status(:unprocessable_entity)
                expect(response.parsed_body[:errors]).to be_a(Hash)
              end
            end
          end

          describe "GET #{controller.pluralize}/:id" do
            it "returns the #{model} with all attributes" do
              get "#{controller}_path/1",
                  headers: { "Authorization" => "Bearer #{access_token}" }
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body).to be_a(Hash)
              expect(response.parsed_body[:id]).to eq(1)
            end

            it "returns 404 for non-existent #{model}" do
              get "#{controller}_path/999",
                  headers: { "Authorization" => "Bearer #{access_token}" }
              expect(response).to have_http_status(:not_found)
            end
          end

          describe "PUT #{controller.pluralize}/:id" do
            it "updates the #{model} and returns 200" do
              put "#{controller}_path/1",
                  params: {
                    "#{controller.downcase}": {
                      id: 1, #{controller.downcase}: { name: "Updated" }
                    }
                  },
                  headers: { "Authorization" => "Bearer #{access_token}" }
              expect(response).to have_http_status(:ok)
              expect(response.parsed_body[:id]).to eq(1)
            end
          end

          describe "DELETE #{controller.pluralize}/:id" do
            it "deletes the #{model} and returns 204" do
              delete "#{controller}_path/1",
                     headers: { "Authorization" => "Bearer #{access_token}" }
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

        require "rails_helper"

        RSpec.describe "#{controller}/#{controller}", type: :feature do
          let(:#{model.downcase}) { create(:#{model.downcase}) }

          describe "user story: Create and view #{model}" do
            it "allows users to create a new #{model} and see it on the dashboard" do
              visit "#{controller.pluralize}s_path"
              within("form") do
                fill_in "#{controller.downcase} Name", with: "Test #{model}"
                click_button "Create #{model}"
              end
              expect(page).to have_content("#{model} was successfully created.")
              expect(page).to have_content("Test #{model}")
            end
          end

          describe "user story: Edit #{model}" do
            it "allows users to edit an existing #{model}" do
              visit "#{controller.pluralize}s_path"
              click_link "Edit #{model}", match: :first
              within("form") do
                fill_in "#{controller.downcase} Name", with: "Updated #{model}"
                click_button "Update #{model}"
              end
              expect(page).to have_content("#{model} was successfully updated.")
              expect(page).to have_content("Updated #{model}")
            end
          end

          describe "user story: Delete #{model}" do
            it "allows users to delete a #{model}" do
              visit "#{controller.pluralize}s_path"
              within(first("a[href*='/#{controller.pluralize}s_path/1']")) do
                click_link "Delete #{model}"
              end
              expect(page).to have_content("#{model} was successfully deleted.")
            end
          end

          describe "user story: View #{model} details" do
            it "displays all #{model} information on the show page" do
              visit "#{controller}_path/#{model.id}"
              expect(page).to have_content("Show #{model}")
              expect(page).to have_content("#{model} Name")
              expect(page).to have_content("#{model} Email")
            end
          end
        end
      TEST

      write_test_file("#{controller}_feature", test_content)
    end

    def write_test_file(subject, content)
      test_path = "#{subject}.test.rb"
      File.write(test_path, content)
      puts "Generated test: #{test_path}"
    end
  end
end
