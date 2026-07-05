# frozen_string_literal: true

module ConjureShield
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def check_ruby_version
        return if RUBY_VERSION >= "3.0.0"

        say "❌ Error: Ruby 3.0.0+ required. Current: #{RUBY_VERSION}", :red
        exit 1
      end

      def check_rails_project
        return if File.exist?(File.join(destination_root, "Gemfile"))

        say "❌ Error: No Gemfile found in #{destination_root}", :red
        exit 1
      end
    end
  end
end