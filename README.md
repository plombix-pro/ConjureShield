# Conjure Shield

Auto Rails test suggestion and implementation generator.

## Installation

### Option 1: Using Installation Script (Recommended)

```bash
bundle exec bin/install
```

This will:
- Validate your Rails project setup
- Check for required dependencies (Rails 7.0+, RSpec, etc.)
- Warn you about missing components
- Install ConjureShield gem locally

### Option 2: Manual Installation

```bash
gem install ConjureShield
```

Or add to your Gemfile:

```ruby
gem "ConjureShield"
```

## Usage

```bash
# Analyze and generate tests
test-suggester --path /path/to/rails/app

# Or use environment variable
CODEBASE_PATH=/path/to/rails/app test-suggester
```

## Features

- 📊 **AST-based Analysis** - Uses Prism to parse Ruby code and extract:
  - Model fields, validations, associations, scopes, callbacks
  - Controller actions, parameters, redirects
  - Serializer inclusions, helper methods

- 🎯 **15+ Test Templates** - Generates specific, contextual tests:
  
  **Model Tests:**
  - Validations (presence, format, uniqueness, inclusion)
  - Validation error messages
  - Associations (has_one, has_many, belongs_to, HABTM)
  - Association validations
  - Custom scopes with arguments
  - Callbacks (before/after save, create, update, destroy)
  - Custom instance methods
  - Factories
  - Serialization (to_json, to_yaml)
  - Delegation

  **Controller Tests:**
  - GET actions (index, show, new, edit)
  - POST actions (create)
  - PUT/PATCH actions (update)
  - DELETE actions (destroy)
  - Pagination, sorting
  - Form rendering
  - Strong parameters (permit/deny)
  - Flash messages
  - Redirects
  - JSON responses

  **Integration Tests:**
  - User workflows (create/view, edit/update, delete)
  - API tests (RESTful endpoints with auth)
  - Feature tests (Capybara-driven)

- 📝 **Context-Aware Generation** - Tests are generated based on:
  - Actual validations found in models
  - Real association types and targets
  - Existing controller actions
  - Current test coverage (avoids duplicates)

- 🔒 **Existing Test Awareness** - Scans `/spec` and `/test` directories to:
  - Detect existing `RSpec.describe` blocks
  - Avoid generating duplicate tests
  - Identify coverage gaps

## Development

```bash
bundle install
bundle exec rake spec
```

## Rake Tasks

```bash
# Validate Rails project setup
bundle exec rake ConjureShield:check_rails

# Validate test framework setup
bundle exec rake ConjureShield:check_tests

# Run all validations
bundle exec rake ConjureShield:validate

# Install ConjureShield
bundle exec rake ConjureShield:install

# Generate tests
bundle exec rake ConjureShield:generate
```

## Requirements

- Ruby >= 3.0.0
- Rails >= 7.0.0
- RSpec >= 3.12.0
- Prism >= 0.29.0
- RuboCop >= 1.50.0 (with rails and rspec extensions)

## License

MIT
