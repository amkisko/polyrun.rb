require "rails_helper"

RSpec.describe "gRPC Demo health", type: :request do
  it "calls Health over an insecure channel (same-process server)" do
    addr = GrpcDemo::TestServer.address
    stub = Demo::V1::Demo::Stub.new(addr, :this_channel_is_insecure)
    reply = stub.health(Demo::V1::HealthRequest.new)
    expect(reply.status).to eq("polyrun-demo")
  end
end
