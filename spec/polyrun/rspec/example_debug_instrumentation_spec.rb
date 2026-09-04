require "spec_helper"
require "stringio"
require "polyrun/rspec/example_debug_instrumentation"

RSpec.describe Polyrun::RSpec::ExampleDebug do
  describe ".sql_with_interpolated_binds" do
    it "replaces positional bind placeholders" do
      sql = "UPDATE users SET name = $1 WHERE id = $2"
      binds = ["Ada", 7]
      expect(described_class.sql_with_interpolated_binds(sql, binds)).to eq(
        "UPDATE users SET name = 'Ada' WHERE id = '7'"
      )
    end
  end

  describe ".install_sql_debug!" do
    it "logs mutating SQL when the around hook runs on an example group" do
      output = StringIO.new
      around_hook = nil
      rspec_config = Object.new
      rspec_config.define_singleton_method(:around) { |&block| around_hook = block }

      subscriber_block = nil
      notifications = Module.new
      notifications.define_singleton_method(:subscribe) do |_name, &block|
        subscriber_block = block
        :sql_debug_subscriber
      end
      notifications.define_singleton_method(:unsubscribe) { |_token| }
      stub_const("ActiveSupport::Notifications", notifications)

      described_class.install_sql_debug!(rspec_config, io: output)

      example = Object.new
      example.define_singleton_method(:run) do
        subscriber_block.call(
          Struct.new(:payload).new({sql: "UPDATE users SET name = $1", type_casted_binds: ["Ada"]})
        )
        subscriber_block.call(
          Struct.new(:payload).new({sql: "SELECT 1", type_casted_binds: []})
        )
      end

      expect { Object.new.instance_exec(example, &around_hook) }.not_to raise_error
      expect(output.string).to include("+ UPDATE users SET name = 'Ada'")
      expect(output.string).not_to include("SELECT")
    end
  end
end
