# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid factory" do
    user = User.new
    assert user.valid?
  end
end
