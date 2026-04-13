require "rails_helper"

RSpec.describe "gRPC Demo catalog", type: :request do
  let(:stub) do
    Demo::V1::Demo::Stub.new(GrpcDemo::TestServer.address, :this_channel_is_insecure)
  end

  it "lists the same items as REST /api/v1/items" do
    reply = stub.list_items(Demo::V1::ListItemsRequest.new)
    expect(reply.items.map(&:slug)).to eq(%w[widget gadget])
  end

  it "returns one item by slug" do
    reply = stub.get_item(Demo::V1::GetItemRequest.new(slug: "gadget"))
    expect(reply.item.slug).to eq("gadget")
    expect(reply.item.title).to eq("Gadget")
  end

  it "returns empty item when slug is unknown" do
    reply = stub.get_item(Demo::V1::GetItemRequest.new(slug: "missing"))
    expect(reply.item).to be_nil
  end
end
