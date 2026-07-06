# frozen_string_literal: true

require "rails_helper"

RSpec.describe "UsersController/UsersController", type: :api do
  describe "GET UsersControllers" do
    it "returns 200 and list of Userss" do
      get "UsersControllerss_path"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_a(Array)
      expect(response.parsed_body).to all(be_a(user))
    end

    it "returns 401 when not authenticated" do
      get "UsersControllerss_path"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST UsersControllerss" do
    context "with valid payload" do
      it "creates a new User and returns 201" do
        post "UsersControllerss_path",
             params: {
               "userscontroller": {
                 id: 1, userscontroller: { name: "Test" }
               }
             },
             headers: { "Authorization" => "Bearer #{access_token}" }
        expect(response).to have_http_status(:created)
        expect(response.parsed_body[:id]).to be_present
        expect(response.parsed_body[:userscontroller]).to be_a(Hash)
      end
    end

    context "with invalid payload" do
      it "returns 422 with validation errors" do
        post "UsersControllerss_path",
             params: {
               "userscontroller": {
                 invalid_field: "value"
               }
             },
             headers: { "Authorization" => "Bearer #{access_token}" }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body[:errors]).to be_a(Hash)
      end
    end
  end

  describe "GET UsersControllers/:id" do
    it "returns the User with all attributes" do
      get "UsersController_path/1",
          headers: { "Authorization" => "Bearer #{access_token}" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_a(Hash)
      expect(response.parsed_body[:id]).to eq(1)
    end

    it "returns 404 for non-existent User" do
      get "UsersController_path/999",
          headers: { "Authorization" => "Bearer #{access_token}" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT UsersControllers/:id" do
    it "updates the User and returns 200" do
      put "UsersController_path/1",
          params: {
            "userscontroller": {
              id: 1, userscontroller: { name: "Updated" }
            }
          },
          headers: { "Authorization" => "Bearer #{access_token}" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body[:id]).to eq(1)
    end
  end

  describe "DELETE UsersControllers/:id" do
    it "deletes the User and returns 204" do
      delete "UsersController_path/1",
             headers: { "Authorization" => "Bearer #{access_token}" }
      expect(response).to have_http_status(:no_content)
    end
  end
end
