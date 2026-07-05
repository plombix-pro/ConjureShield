module Conjureshield
  class Railtie < Rails::Railtie
    rake_tasks do
      # This glob finds all .rake files in your tasks directory
      Dir[File.join(File.dirname(__FILE__), '/tasks/*.rake')].each { |f| load f }
    end

    initializer "conjureshield.post_install_message" do |app|
      next unless Rails.env.development?
      next if Conjureshield.install_shown

      Conjureshield.install_shown = true

      puts "\n" + "=" * 60
      puts "🛡️  ConjureShield - Rails Test Generator Installed!"
      puts "=" * 60
      puts "\n📚 What it does:"
      puts "   • Analyzes your Rails models, controllers, and callbacks"
      puts "   • Identifies missing test coverage"
      puts "   • Generates RSpec tests to approach 100% coverage"
      puts "\n🚀 Available Rake Tasks:"
      puts "   rake conjureshield:validate   - Check Rails setup"
      puts "   rake conjureshield:analyze    - Analyze codebase"
      puts "   rake conjureshield:generate   - Generate tests"
      puts "   rake conjureshield:check_tests - Check coverage"
      puts "   rake conjureshield:full       - Run all tasks"
      puts "\n💡 Quick Start:"
      puts "   1. Run: bundle exec conjure-shield validate"
      puts "   2. Review suggestions in output"
      puts "   3. Run: bundle exec conjure-shield generate"
      puts "\n📖 Learn more: https://github.com/plombix-pro/ConjureShield"
      puts "=" * 60 + "\n"
    end
  end
end
