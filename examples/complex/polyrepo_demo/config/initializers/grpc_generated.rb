# Generated protobuf / gRPC stubs live under lib/grpc_generated (see script/grpc_codegen).
return unless Rails.env.test?

$LOAD_PATH.unshift(Rails.root.join("lib/grpc_generated").to_s)
require "demo/v1/demo_pb"
require "demo/v1/demo_services_pb"
