# frozen_string_literal: true

require "rails_helper"

RSpec.describe "UsersController", type: :request do
  describe "GET show action" do
    it "returns success response" do
      get "userscontrollers_path/userscontroller_id"
      expect(response).to have_http_status(:ok)
    end

    it "renders show template" do
      get "userscontrollers_path/userscontroller_id"
      expect(response).to render_template(:show)
    end

    it "passes correct instance variables" do
      get "userscontrollers_path/userscontroller_id"
      expect(assigns(:userscontroller)).to be_present
    end
  end
end
