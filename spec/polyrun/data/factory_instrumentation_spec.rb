require "spec_helper"

RSpec.describe Polyrun::Data::FactoryInstrumentation do
  before do
    Polyrun::Data::FactoryCounts.reset!
    stub_const("FactoryBot", Module.new)
    stub_const("FactoryBot::Factory", Class.new do
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def run(_build_strategy, _overrides = {})
        :ran
      end
    end)
  end

  it "prepends Factory and records FactoryCounts" do
    expect(described_class.instrument_factory_bot!).to be true
    f = FactoryBot::Factory.new(:widget)
    f.run(:create, {})
    expect(Polyrun::Data::FactoryCounts.counts["widget"]).to eq(1)
  end

  it "is idempotent" do
    expect(described_class.instrument_factory_bot!).to be true
    expect(described_class.instrument_factory_bot!).to be true
    expect(described_class.instrumented?).to be true
  end
end
