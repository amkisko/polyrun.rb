require "rails_helper"

# One process exercises REST + GraphQL + gRPC clients — coverage merges across Polyrun shards
# still attribute hits to the right files when you split by directory or tag.
RSpec.describe "Multi-client flow (REST + GraphQL + gRPC)", type: :request do
  it "aggregates the same catalog across protocols" do
    get "/api/v1/items"
    rest_slugs = response.parsed_body["items"].map { |i| i["slug"] }

    post "/graphql",
      params: {query: "{ items { slug } }"},
      headers: {"Content-Type" => "application/json"},
      as: :json
    gql_slugs = response.parsed_body.dig("data", "items").map { |h| h["slug"] }

    addr = GrpcDemo::TestServer.address
    stub = Demo::V1::Demo::Stub.new(addr, :this_channel_is_insecure)
    grpc_ok = stub.health(Demo::V1::HealthRequest.new).status

    get "/api/v1/health"
    health_verticals = response.parsed_body.fetch("verticals").map { |v| v["slug"] }

    expect(rest_slugs.sort).to eq(gql_slugs.sort)
    expect(grpc_ok).to eq("polyrun-demo")
    expect(health_verticals).to include("banking", "forum")
  end
end
