require "spec_helper"
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
end
