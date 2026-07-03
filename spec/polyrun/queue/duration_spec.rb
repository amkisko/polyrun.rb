require "spec_helper"

RSpec.describe Polyrun::Queue::Duration do
  describe ".parse_seconds" do
    it "parses plain seconds" do
      expect(described_class.parse_seconds("600")).to eq(600.0)
      expect(described_class.parse_seconds("1.5")).to eq(1.5)
    end

    it "parses suffixed durations" do
      expect(described_class.parse_seconds("10s")).to eq(10.0)
      expect(described_class.parse_seconds("10m")).to eq(600.0)
      expect(described_class.parse_seconds("1h")).to eq(3600.0)
      expect(described_class.parse_seconds("1d")).to eq(86_400.0)
    end

    it "raises on invalid input" do
      expect { described_class.parse_seconds("nope") }.to raise_error(Polyrun::Error, /invalid duration/)
    end
  end
end
