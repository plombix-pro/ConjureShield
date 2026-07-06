require 'fileutils'
namespace :conjureshield do
  desc "Validate Rails project setup for ConjureShield"
  task :validate do
    codebase = File.expand_path(ENV.fetch("CODEBASE_PATH") { Dir.pwd })
    all_passed = true
  
    # 1. Verify if it is a Rails app by checking for bin/rails
    rails_bin = File.join(codebase, "bin", "rails")
    if File.exist?(rails_bin) && File.executable?(rails_bin)
      puts "✅ Rails project detected"
    else
      puts "❌ Not a valid Rails project (bin/rails not found or not executable)"
      all_passed = false
    end
  
    # 2. Check for database.yml (Optional but recommended)
    db_config = File.join(codebase, "config", "database.yml")
    if File.exist?(db_config)
      puts "✅ config/database.yml"
    else
      puts "❌ config/database.yml missing"
      all_passed = false
    end
  
    # 3. Handle 'spec/' directory with auto-creation
    spec_path = File.join(codebase, "spec")
    if Dir.exist?(spec_path)
      puts "✅ spec/"
    else
      puts "⚠️  spec/ directory missing. Creating it for you..."
      FileUtils.mkdir_p(spec_path)
      puts "✅ spec/ (created successfully)"
    end
  
    # 4. Final status
    if all_passed
      puts "\n✅ Rails project is ready for ConjureShield!"
    else
      puts "\n⚠️  Some checks failed. Please fix the issues above."
      exit 1
    end
  end

  desc "Analyze Rails app and show missing tests"
  task :analyze do
    codebase = ENV.fetch("CODEBASE_PATH") { Dir.pwd }
    codebase = File.expand_path(codebase)

    puts "🔍 ConjureShield - Rails Test Generator"
    puts "=" * 50
    puts "📁 Analyzing: #{codebase}"
    puts "=" * 50

    analyzer = Conjureshield.analyze(codebase)

    puts "\n📊 Analysis Results:"
    puts "-" * 50
    puts "Files analyzed: #{analyzer.files.count}"
    puts "Models found: #{analyzer.ast_nodes.count { |n| n[:type] == :model }}"
    puts "Controllers found: #{analyzer.ast_nodes.count { |n| n[:type] == :controller }}"
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
    codebase = ENV.fetch("CODEBASE_PATH") { Dir.pwd }
    codebase = File.expand_path(codebase)

    rails_helper = File.join(codebase, "spec", "rails_helper.rb")
    spec_helper = File.join(codebase, "spec", "spec_helper.rb")
    unless File.exist?(rails_helper) || File.exist?(spec_helper)
      puts "\n⚠️  spec/rails_helper.rb or spec/spec_helper.rb not found."
      puts "   Running rails generate conjure_shield:install first..."
      Rails::Generators.invoke("conjure_shield:install", [], destination_root: codebase)
    end

    puts "\n🎯 Generating test implementations..."
    puts "=" * 50

    analyzer = Conjureshield.analyze(codebase)

    if analyzer.missing_tests.any?
      puts "📝 Generating #{analyzer.missing_tests.count} test file(s)..."
      Conjureshield.generate_tests(analyzer.files, analyzer.missing_tests)
      puts "\n✅ Tests generated! Check spec/ directory."
      puts ""
      puts "⚠️  WARNING: THESE ARE GENERIC TEMPLATES. YOU MUST HEAVILY ADAPT"
      puts "⚠️  EACH TEST TO MATCH YOUR ACTUAL APPLICATION CODE AND LOGIC."
      puts ""
    else
      puts "⚠️  No missing tests detected. All features appear to be covered."
    end
  end

  desc "Check test coverage and setup"
  task :check_tests do
    codebase = ENV.fetch("CODEBASE_PATH") { Dir.pwd }
    codebase = File.expand_path(codebase)
    analyzer = Conjureshield.analyze(codebase)

    puts "🔍 ConjureShield - Test Setup Check"
    puts "=" * 50

    puts "\n📊 Test Infrastructure:"
    puts "-" * 50
    puts "RSpec tests: #{Dir.glob(File.join(codebase, "spec/**/*.rb")).count}"
    puts "Minitest tests: #{Dir.glob(File.join(codebase, "test/**/*.rb")).count}"

    puts "\n📊 Code Analysis:"
    puts "-" * 50
    puts "Models: #{analyzer.ast_nodes.count { |n| n[:type] == :model }}"
    puts "Controllers: #{analyzer.ast_nodes.count { |n| n[:type] == :controller }}"

    puts "\n📊 Coverage Analysis:"
    puts "-" * 50
    models = analyzer.ast_nodes.select { |n| n[:type] == :model }
    model_prefixes = models.map { |m| "#{m[:model].underscore}_" }

    models.each do |model|
      model_prefix = "#{model[:model].underscore}_"
      longer_prefixes = model_prefixes.select { |p| p != model_prefix && p.start_with?(model_prefix) }

      all = Dir.glob(File.join(codebase, "spec", "#{model_prefix}*_spec.rb"))
      all.reject! { |f| longer_prefixes.any? { |lp| File.basename(f).start_with?(lp) } }

      puts "  #{model[:model]}: #{all.count} test file(s) found"
    end
  end

  desc "Run all tasks: validate, analyze, generate, check"
  task :full => [:validate, :analyze, :generate, :check_tests]
end
