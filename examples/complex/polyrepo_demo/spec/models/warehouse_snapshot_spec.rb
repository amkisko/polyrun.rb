require "rails_helper"

RSpec.describe WarehouseSnapshot, type: :model do
  it "writes to the warehouse database" do
    described_class.create!(name: "e2e-shard-demo")
    expect(described_class.count).to eq(1)
  end
end
