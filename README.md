# Conjure Shield
Bored of create the folders and files needed to test your app ? 
Get you 100% code coverage quicker !
Conjure a Shield for your app : 

Auto Rails test suggestion and implementation generator. Supports both **RSpec** and **Minitest**.

## Installation

Add to your Gemfile:

```ruby
gem "conjure_shield"
```

Or install directly:

```bash
gem install conjure_shield
```

Then run the install generator:

```bash
rails generate conjure_shield:install
```

This adds the following gems to your `:development, :test` group and configures them:

- `rspec-rails` — RSpec testing framework
- `rails-controller-testing` — `assigns` / `assert_template` helpers
- `shoulda-matchers` — one-liner matchers for models
- `factory_bot_rails` — factory-based test data
- `capybara` — feature/integration tests (optional)
- `database_cleaner-active_record` — transactional test cleanup

The generator also:

- Runs `rails generate rspec:install`
- Configures Shoulda Matchers in `spec/rails_helper.rb`
- Configures DatabaseCleaner for both `spec/support/database_cleaner.rb` (RSpec) and `test/test_helper.rb` (Minitest)
- Replaces scaffold-generated fixture files with comments pointing to FactoryBot factories

## Usage

```bash
# Analyze and generate tests
bundle exec rake conjureshield:full

# Or target a specific path
CODEBASE_PATH=/path/to/rails/app bundle exec rake conjureshield:full
```

## Rake Tasks

```bash
# Validate Rails project setup
bundle exec rake conjureshield:validate

# Analyze codebase for missing tests
bundle exec rake conjureshield:analyze

# Generate test files (factories + skeletons)
bundle exec rake conjureshield:generate

# Check test coverage
bundle exec rake conjureshield:check_tests

# Run all tasks
bundle exec rake conjureshield:full
```

## What gets generated

ConjureShield generates tests for **both RSpec and Minitest** when both `spec/` and `test/` directories exist:

| Directory | Framework | Extension |
|-----------|-----------|-----------|
| `spec/factories/` | Both | `*.rb` |
| `spec/*_spec.rb` | RSpec | `_spec.rb` |
| `test/factories/` | Both | `*.rb` |
| `test/*_test.rb` | Minitest | `_test.rb` |

### Factories (uncommented, ready to use)

Every model gets a real FactoryBot factory in `spec/factories/` derived from `db/schema.rb`:

- **Typed attributes** per schema column (`sequence` for `email`/`*_email` fields)
- **`belongs_to`** — top-level `association`
- **`has_one` / `has_many` / `has_one_through`** — `with_*` traits
- **`has_and_belongs_to_many` / `has_many_through`** — `with_*` traits with `after(:create)` push
- **Namespaced models** — `factory :admin_article, class: "Admin::Article"`

### Test skeletons (commented out, `## frozen_string_literal: true`)

All generated test files are fully commented out so they never break your suite. Each line starts with `#` (including `## frozen_string_literal: true`). To activate a test, uncomment the lines you need (removing one `#`).

**Model tests:** validations, associations, scopes, callbacks, custom methods, serialization, delegation

**Controller tests:** index (pagination, sorting), show (with associations), new/edit forms, create (valid/invalid/redirect), update (valid/invalid/redirect), destroy (redirect), strong parameters (permit/deny)

## Keeping tests in sync

Re-run the generator after adding models, controllers, associations, or columns:

```bash
bundle exec rake conjureshield:generate
```

- **New models/controllers** without a test file get commented-out skeletons
- **Existing test files** are never overwritten
- **Factories** are generated once and never overwritten on subsequent runs

## Example generated factory

```ruby
# spec/factories/article.rb
FactoryBot.define do
  factory :article do
    title { "title" }
    body { "sample text" }
    published { false }

    association :author            # belongs_to

    trait :with_comments do        # has_many
      association :comments
    end

    trait :with_tags do            # has_and_belongs_to_many
      after(:create) do |article, evaluator|
        article.tags << create(:tag)
      end
    end
  end
end
```

## Example generated test skeleton (Minitest)

```ruby
## frozen_string_literal: true
#
# require "test_helper"
#
# class ArticleTest < ActiveSupport::TestCase
#   test "validates title" do
#     record = Article.new
#     record.valid?
#     assert_not record.errors[:title].empty?, "title should be validated"
#   end
# end
```

Uncomment the relevant lines to activate.

## Requirements

- Ruby >= 3.0.0
- Rails >= 7.0.0
- RSpec >= 3.12.0 (optional — Minitest works out of the box)
- Prism >= 0.29.0
- RuboCop >= 1.50.0 (with rails and rspec extensions)

## License

MIT
