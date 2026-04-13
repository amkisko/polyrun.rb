require "rails_helper"

# Exercises the same domain model through REST, GraphQL, and gRPC in one example — ideal for
# coverage maps and Polyrun shard splits (e.g. partition by directory: spec/grpc vs spec/requests).
RSpec.describe "Catalog parity (REST + GraphQL + gRPC)", type: :request do
  it "keeps slugs and titles aligned across every protocol" do
    get "/api/v1/catalog"
    rest = response.parsed_body
    rest_slugs = rest.fetch("items").map { |i| i["slug"] }.sort

    post "/graphql",
      params: {
        query: <<~GQL
          {
            items { slug title }
            w: item(slug: "widget") { slug title }
            g: item(slug: "gadget") { slug title }
          }
        GQL
      },
      headers: {"Content-Type" => "application/json"},
      as: :json
    data = response.parsed_body.fetch("data")
    gql_slugs = data.fetch("items").map { |h| h["slug"] }.sort
    expect(data.dig("w", "slug")).to eq("widget")
    expect(data.dig("g", "title")).to eq("Gadget")

    stub = Demo::V1::Demo::Stub.new(GrpcDemo::TestServer.address, :this_channel_is_insecure)
    list = stub.list_items(Demo::V1::ListItemsRequest.new)
    grpc_slugs = list.items.map(&:slug).sort
    widget = stub.get_item(Demo::V1::GetItemRequest.new(slug: "widget"))

    expect(rest_slugs).to eq(gql_slugs)
    expect(rest_slugs).to eq(grpc_slugs)
    expect(widget.item.title).to eq("Widget")
  end
end
