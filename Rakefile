require "bundler/setup"
require "conjure_shield"

namespace :conjureshield do
  desc "Analyze Rails app and generate tests"
  task :analyze do
    puts "🔍 ConjureShield - Rails Test Generator"
    puts "=" * 50

    codebase = ENV.fetch("CODEBASE_PATH") { "." }
    puts "📁 Analyzing: #{codebase}"
    puts "=" * 50

    analyzer = ConjureShield.analyze(codebase)

    puts "\n📊 Analysis Results:"
    puts "-" * 50
    puts "Files analyzed: #{analyzer.files.count}"
    puts "Models found: #{analyzer.ast_nodes.count { |n| n[:type] == :model }}"
    puts "Controllers found: #{analyzer.ast_nodes.count { |n| n[:type] == :controller }}"
    puts "Callbacks found: #{analyzer.ast_nodes.count { |n| n[:type] == :callbacks }}"
    puts "Scopes found: #{analyzer.ast_nodes.count { |n| n[:type] == :scopes }}"
    puts "Validations found: #{analyzer.ast_nodes.count { |n| n[:type] == :validations }}"
    puts "Associations found: #{analyzer.ast_nodes.count { |n| n[:type] == :associations }}"
    puts "Custom methods found: #{analyzer.ast_nodes.count { |n| n[:type] == :custom_methods }}"
    puts "Missing tests: #{analyzer.missing_tests.count}"

    if analyzer.missing_tests.any?
      puts "\n📋 Suggested Tests:"
      puts "-" * 50
      analyzer.missing_tests.each_with_index do |test, i|
        puts "\n#{i + 1}. #{test[:type].to_s.capitalize}"
        test[:suggestions]&.each do |suggestion|
          puts "   • #{suggestion[:name]}"
        end
      end
    end
  end

  desc "Generate test files based on analysis"
  task :generate => :analyze do
    puts "\n🎯 Generating test implementations..."
    puts "=" * 50

    codebase = ENV.fetch("CODEBASE_PATH") { "." }
    analyzer = ConjureShield.analyze(codebase)

    if analyzer.missing_tests.any?
      puts "📝 Generating #{analyzer.missing_tests.count} example files..."
      ConjureShield.generate_tests(analyzer.files, analyzer.missing_tests)
      puts "\n✅ Example files generated in spec/. Each file is commented out —"
      puts "   uncomment and adapt to match your application logic."
    else
      puts "⚠️  No missing tests detected. All features appear to be covered."
    end
  end

  desc "Run full analysis and generate tests"
  task :run => :generate

  desc "Validate Rails project setup"
  task :validate do
    puts "🔍 ConjureShield - Rails Validation"
    puts "=" * 50

    codebase = ENV.fetch("CODEBASE_PATH") { "." }
    codebase = File.expand_path(codebase)

    checks = {
      "config/application.rb" => File.exist?(File.join(codebase, "config", "application.rb")),
      "Gemfile" => File.exist?(File.join(codebase, "Gemfile")),
      "Gemfile.lock" => File.exist?(File.join(codebase, "Gemfile.lock")),
      "spec/" => Dir.exist?(File.join(codebase, "spec")),
      "test/" => Dir.exist?(File.join(codebase, "test")),
      "config/database.yml" => File.exist?(File.join(codebase, "config", "database.yml"))
    }

    all_passed = true
    checks.each do |name, passed|
      status = passed ? "✅" : "❌"
      puts "#{status} #{name}"
      all_passed = false unless passed
    end

    if all_passed
      puts "\n✅ Rails project is ready for ConjureShield!"
    else
      puts "\n⚠️  Some checks failed. Please fix the issues above."
      exit 1
    end
  end

  desc "Check test coverage and setup"
  task :check_tests do
    puts "🔍 ConjureShield - Test Setup Check"
    puts "=" * 50

    codebase = ENV.fetch("CODEBASE_PATH") { "." }
    codebase = File.expand_path(codebase)

    analyzer = ConjureShield.analyze(codebase)

    puts "\n📊 Test Infrastructure:"
    puts "-" * 50
    puts "RSpec tests: #{Dir.glob(File.join(codebase, "spec/**/*.rb")).count}"
    puts "Minitest tests: #{Dir.glob(File.join(codebase, "test/**/*.rb")).count}"

    puts "\n📊 Code Analysis:"
    puts "-" * 50
    puts "Models: #{analyzer.ast_nodes.count { |n| n[:type] == :model }}"
    puts "Controllers: #{analyzer.ast_nodes.count { |n| n[:type] == :controller }}"
    puts "Helpers: #{analyzer.ast_nodes.count { |n| n[:type] == :helper }}"

    puts "\n📊 Coverage Analysis:"
    puts "-" * 50

    models = analyzer.ast_nodes.select { |n| n[:type] == :model }
    controllers = analyzer.ast_nodes.select { |n| n[:type] == :controller }

    models.each do |model|
      model_name = model[:model]
      model_tests = Dir.glob(File.join(codebase, "spec/models/#{model_name.downcase}*.rb")).count
      model_spec = Dir.glob(File.join(codebase, "spec/models/#{model_name.downcase}_spec.rb")).count

      puts "  #{model_name}: #{model_tests + model_spec} test file(s) found"
    end

    controllers.each do |controller|
      controller_name = controller[:controller]
      controller_tests = Dir.glob(File.join(codebase, "spec/controllers/#{controller_name.downcase}*.rb")).count
      controller_spec = Dir.glob(File.join(codebase, "spec/controllers/#{controller_name.downcase}_controller_spec.rb")).count

      puts "  #{controller_name}: #{controller_tests + controller_spec} test file(s) found"
    end
  end

  desc "Run all tasks: validate, analyze, generate, check"
  task :full => [:validate, :analyze, :generate, :check_tests]
end

task :conjure => "conjureshield:run"
