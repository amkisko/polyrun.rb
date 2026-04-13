require "rails_helper"

RSpec.describe "Api::V1::Catalog", type: :request do
  it "returns a unified snapshot for multi-protocol clients" do
    get "/api/v1/catalog"
    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json["service"]).to eq("polyrepo-complex-demo")
    expect(json["items"].map { |i| i["slug"] }).to eq(%w[widget gadget])
    expect(json["verticals"].map { |v| v["slug"] }).to include("banking", "analytics")
  end
end
