# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FactoryBot factories for User" do
  it "creates valid user instances" do
    factory = FactoryBot.build(:user)
    expect(factory).to be_valid
  end

  it "creates user with default values" do
    factory = FactoryBot.build(:user)
    expect(factory).to have_attributes(default_attributes)
  end

  it "creates user with custom values" do
    factory = FactoryBot.build(:user, custom_attrs: "value")
    expect(factory).to have_attributes(custom_attrs: "value")
  end
end
