module Conjureshield
  class Templates
    # 1. Define this as a proper constant at the top
    EXAMPLES_PATH = "/tmp/rspec-examples"

    attr_reader :examples

    def initialize
      # 2. Call the class method explicitly using self.class
      @examples = self.class.load_rspec_examples
    end

    def self.load
      new
    end

    def self.load_rspec_examples
      return [] unless File.exist?(EXAMPLES_PATH)

      examples = []
      parse_file(EXAMPLES_PATH, examples)
      examples
    end

    def self.parse_file(file, examples)
      return unless File.exist?(file)

      content = File.read(file)
      examples << { file: file, content: content }

      Dir.glob("#{file}/**/*.rb").each do |subfile|
        parse_file(subfile, examples)
      end
    end

    def self.get_template(type, context = {})
      templates = {
        model: [
          :validations, :associations, :scopes, :callbacks, :factories, :custom_attributes, :delegation
        ],
        controller: [
          :get_actions, :post_actions, :put_patch_actions, :delete_actions, :parameters, :redirects, :flash_messages, :json_responses
        ],
        request: [
          :authentication, :authorization, :api_responses, :rate_limiting, :caching
        ],
        job: [
          :queues, :errors, :timeouts, :retry_logic, :sidekiq_testing
        ],
        mailer: [
          :delivery, :templates, :attachments, :default_parameters
        ],
        form: [
          :strong_parameters, :nested_attributes, :collection_selects, :file_uploads
        ],
        integration: [
          :workflow, :state_machines, :external_services, :database_transactions
        ]
      }

      templates[type] || []
    end
  end
end