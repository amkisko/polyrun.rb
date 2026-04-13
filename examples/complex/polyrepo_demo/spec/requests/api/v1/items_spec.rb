require "rails_helper"

RSpec.describe "Api::V1::Items", type: :request do
  it "lists items" do
    get "/api/v1/items"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].size).to eq(2)
  end

  it "shows one item by slug" do
    get "/api/v1/items/widget"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["item"]["slug"]).to eq("widget")
  end
end
