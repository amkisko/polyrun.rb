require "spec_helper"

RSpec.describe Polyrun::Data::FactoryCounts do
  it "records and summarizes" do
    described_class.reset!
    described_class.record(:user)
    described_class.record(:user)
    described_class.record(:post)
    expect(described_class.counts["user"]).to eq(2)
    expect(described_class.format_summary).to include("user: 2")
  end
end
