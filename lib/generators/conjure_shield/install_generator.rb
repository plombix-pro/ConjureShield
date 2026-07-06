# frozen_string_literal: true

module ConjureShield
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

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
    end
  end
end
