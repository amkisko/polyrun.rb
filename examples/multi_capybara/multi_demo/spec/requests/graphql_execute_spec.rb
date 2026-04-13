require "rails_helper"

RSpec.describe "GraphQL execute", type: :request do
  it "returns health" do
    post "/graphql",
      params: {query: "{ health }"},
      headers: {"Content-Type" => "application/json"},
      as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "health")).to eq("ok")
  end

  it "returns items" do
    post "/graphql",
      params: {query: "{ items { slug title } }"},
      headers: {"Content-Type" => "application/json"},
      as: :json
    items = response.parsed_body.dig("data", "items")
    expect(items.map { |h| h["slug"] }).to include("widget", "gadget")
  end

  it "returns verticals" do
    post "/graphql",
      params: {query: "{ verticals }"},
      headers: {"Content-Type" => "application/json"},
      as: :json
    verticals = response.parsed_body.dig("data", "verticals")
    expect(verticals).to include("banking", "analytics")
  end

  it "returns a single item by slug" do
    post "/graphql",
      params: {query: '{ item(slug: "widget") { slug title } }'},
      headers: {"Content-Type" => "application/json"},
      as: :json
    item = response.parsed_body.dig("data", "item")
    expect(item["slug"]).to eq("widget")
    expect(item["title"]).to eq("Widget")
  end
end
