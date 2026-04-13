# In-process gRPC server for specs (demo.v1.Demo). Requires config/initializers/grpc_generated.rb (test env).
class GrpcDemoHandler < Demo::V1::Demo::Service
  def health(_req, _call)
    Demo::V1::HealthReply.new(status: "polyrun-demo")
  end

  def list_items(_req, _call)
    items = Catalog.items.map { |h| item_pb_from_row(h) }
    Demo::V1::ListItemsReply.new(items: items)
  end

  def get_item(req, _call)
    row = Catalog.find_by_slug(req.slug)
    item = row ? item_pb_from_row(row) : nil
    Demo::V1::GetItemReply.new(item: item)
  end

  private

  def item_pb_from_row(h)
    Demo::V1::Item.new(id: h[:id], slug: h[:slug], title: h[:title])
  end
end

module GrpcDemo
  module TestServer
    module_function

    def address
      @address
    end

    def start!
      return if @server

      @server = GRPC::RpcServer.new
      port = @server.add_http2_port("127.0.0.1:0", :this_port_is_insecure)
      @server.handle(GrpcDemoHandler)
      @runner = Thread.new { @server.run }
      @server.wait_till_running(5)
      @address = "127.0.0.1:#{port}"
    end

    def stop!
      return unless @server

      @server.stop
      @runner&.join(5)
      @server = nil
      @runner = nil
      @address = nil
    end
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    GrpcDemo::TestServer.start!
  end

  config.after(:suite) do
    GrpcDemo::TestServer.stop!
  end
end
