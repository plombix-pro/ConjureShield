module ConjureShield
  class Railtie < Rails::Railtie
    rake_tasks do
      # This glob finds all .rake files in your tasks directory
      Dir[File.join(File.dirname(__FILE__), '/tasks/*.rake')].each { |f| load f }
    end

    initializer "conjureshield.post_install_message" do |app|
      next unless Rails.env.development?
      next if ConjureShield.install_shown

      ConjureShield.install_shown = true

      puts "\n" + "=" * 60
      puts "🛡️  ConjureShield - Rails Test Generator Installed!"
      puts "=" * 60
      puts "\n📚 What it does:"
      puts "   • Analyzes your Rails models, controllers, and callbacks"
      puts "   • Identifies missing test coverage"
      puts "   • Generates skeleton RSpec example files (all content commented out)"
      puts "\n🚀 Available Rake Tasks:"
      puts "   rake conjureshield:validate      - Check Rails setup"
      puts "   rake conjureshield:analyze       - Analyze codebase"
      puts "   rake conjureshield:generate      - Generate example files"
      puts "   rake conjureshield:check_tests   - Check coverage"
      puts "   rake conjureshield:full          - Run all tasks"
      puts "\n💡 Quick Start:"
      puts "   1. Run: rake conjureshield:full"
      puts "   2. Review suggestions & open generated spec/ files"
      puts "   3. Uncomment and adapt tests to match your app logic"
      puts "\n📖 Learn more: https://github.com/plombix-pro/ConjureShield"
      puts "=" * 60 + "\n"
    end
  end
end
