# frozen_string_literal: true

module ConjureShield
  module Generators
    class InstallGenerator < ::Rails::Generators::Base

      def check_ruby_version
        return if RUBY_VERSION >= "3.0.0"

        say "Error: Ruby 3.0.0+ required. Current: #{RUBY_VERSION}", :red
        exit 1
      end

      def check_rails_project
        return if File.exist?(File.join(destination_root, "Gemfile"))

        say "Error: No Gemfile found in #{destination_root}", :red
        exit 1
      end

      def ensure_test_gems
        gemfile = File.join(destination_root, "Gemfile")
        content = File.read(gemfile)
        needs_bundle = false

        unless content.include?("rspec-rails")
          say "Adding rspec-rails to Gemfile...", :blue
          if content =~ /^group :development, :test do\b/
            content.gsub!(/^group :development, :test do\b/) do |match|
              match + "\n" + "  gem \"rspec-rails\"\n"
            end
            needs_bundle = true
            say "  Added gem 'rspec-rails' to group :development, :test", :green
          end
        end

        unless content.include?("rails-controller-testing")
          say "Adding rails-controller-testing to Gemfile...", :blue
          if content =~ /^group :development, :test do\b/
            content.gsub!(/^group :development, :test do\b/) do |match|
              match + "\n" + "  gem \"rails-controller-testing\"\n"
            end
            needs_bundle = true
            say "  Added gem 'rails-controller-testing' to group :development, :test", :green
          end
        end

        unless content.include?("shoulda-matchers")
          say "Adding shoulda-matchers to Gemfile...", :blue
          if content =~ /^group :development, :test do\b/
            content.gsub!(/^group :development, :test do\b/) do |match|
              match + "\n" + "  gem \"shoulda-matchers\"\n"
            end
            needs_bundle = true
            say "  Added gem 'shoulda-matchers' to group :development, :test", :green
          end
        end

        unless content.include?("factory_bot_rails")
          say "Adding factory_bot_rails to Gemfile...", :blue
          if content =~ /^group :development, :test do\b/
            content.gsub!(/^group :development, :test do\b/) do |match|
              match + "\n" + "  gem \"factory_bot_rails\"\n"
            end
            needs_bundle = true
            say "  Added gem 'factory_bot_rails' to group :development, :test", :green
          end
        end

        unless content.include?("capybara")
          say "Adding capybara to Gemfile...", :blue
          if content =~ /^group :development, :test do\b/
            content.gsub!(/^group :development, :test do\b/) do |match|
              match + "\n" + "  gem \"capybara\"\n"
            end
            needs_bundle = true
            say "  Added gem 'capybara' to group :development, :test", :green
          end
        end

        unless content.include?("database_cleaner-active_record")
          say "Adding database_cleaner-active_record to Gemfile...", :blue
          if content =~ /^group :development, :test do\b/
            content.gsub!(/^group :development, :test do\b/) do |match|
              match + "\n" + "  gem \"database_cleaner-active_record\"\n"
            end
            needs_bundle = true
            say "  Added gem 'database_cleaner-active_record' to group :development, :test", :green
          end
        end

        if needs_bundle
          File.write(gemfile, content)
        end
      end

      def run_bundle_install
        say "Running bundle install...", :blue
        Bundler.with_unbundled_env { system("bundle install") }
        Bundler.reset!
      end

      def run_rspec_install
        say "Running rails generate rspec:install...", :blue
        system("rails generate rspec:install")
      end

      def configure_shoulda_matchers
        spec_helper = File.join(destination_root, "spec", "rails_helper.rb")
        return unless File.exist?(spec_helper)

        content = File.read(spec_helper)
        config_block = <<~RUBY

          Shoulda::Matchers.configure do |config|
            config.integrate do |with|
              with.test_framework :rspec
              with.library :rails
            end
          end
        RUBY

        unless content.include?("Shoulda::Matchers.configure")
          content.gsub!(/^end\s*\z/, config_block + "\nend")
          File.write(spec_helper, content)
          say "  Configured shoulda-matchers in spec/rails_helper.rb", :green
        end
      end

      def replace_fixtures_with_comments
        fixtures_dir = File.join(destination_root, "test", "fixtures")
        return unless File.directory?(fixtures_dir)

        Dir.glob(File.join(fixtures_dir, "*.yml")).each do |fixture_file|
          content = File.read(fixture_file)
          next if content.lines.first&.include?("Use FactoryBot")

          model_name = File.basename(fixture_file, ".yml")
          File.write(fixture_file, <<~YAML)
            # Use FactoryBot instead of fixtures. See spec/factories/#{model_name}.rb
          YAML
          say "  Replaced #{fixture_file} with factory comment", :green
        end
      end

      def configure_database_cleaner
        rspec_support_dir = File.join(destination_root, "spec", "support")
        rspec_cleaner = File.join(rspec_support_dir, "database_cleaner.rb")

        if File.exist?(File.join(destination_root, "spec", "rails_helper.rb")) && !File.exist?(rspec_cleaner)
          FileUtils.mkdir_p(rspec_support_dir)
          File.write(rspec_cleaner, <<~RUBY)
            # frozen_string_literal: true

            RSpec.configure do |config|
              config.before(:suite) do
                DatabaseCleaner.strategy = :transaction
                DatabaseCleaner.clean_with(:truncation)
              end

              config.around(:each) do |example|
                DatabaseCleaner.cleaning do
                  example.run
                end
              end
            end
          RUBY
          say "  Created spec/support/database_cleaner.rb", :green
        end

        test_helper = File.join(destination_root, "test", "test_helper.rb")
        if File.exist?(test_helper)
          content = File.read(test_helper)
          cleaner_config = <<~RUBY

            DatabaseCleaner.strategy = :transaction
            DatabaseCleaner.clean_with(:truncation)

            class ActiveSupport::TestCase
              setup { DatabaseCleaner.start }
              teardown { DatabaseCleaner.clean }
            end
          RUBY

          unless content.include?("DatabaseCleaner")
            content.gsub!(/^end\s*\z/, cleaner_config + "\nend")
            File.write(test_helper, content)
            say "  Configured DatabaseCleaner in test/test_helper.rb", :green
          end
        end
      end
    end
  end
end
