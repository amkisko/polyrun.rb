require "rails_helper"

RSpec.describe "Api::V1::Health", type: :request do
  it "returns JSON health" do
    get "/api/v1/health"
    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json["status"]).to eq("ok")
    expect(json["protocols"]).to include("rest", "graphql", "grpc")
    verticals = json["verticals"]
    expect(verticals).to be_an(Array)
    expect(verticals.map { |v| v["slug"] }).to include("banking", "analytics")
    expect(verticals.find { |v| v["slug"] == "banking" }["label"]).to eq("Retail Banking")
  end
end
