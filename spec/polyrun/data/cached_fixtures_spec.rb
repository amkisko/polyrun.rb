require "spec_helper"

RSpec.describe Polyrun::Data::CachedFixtures do
  before do
    described_class.reset!
    described_class.enable!
  end

  it "memoizes register/fetch per key" do
    n = 0
    a = described_class.fetch(:x) do
      n += 1
      :first
    end
    b = described_class.fetch(:x) do
      n += 1
      :second
    end
    expect(a).to eq(:first)
    expect(b).to eq(:first)
    expect(n).to eq(1)
  end

  it "tracks hit stats" do
    described_class.fetch(:k) { 1 }
    described_class.fetch(:k) { 2 }
    st = described_class.stats["k"]
    expect(st[:hits]).to eq(1)
    expect(st[:build_time]).to be >= 0.0
  end

  it "runs reset callbacks and clears cache" do
    seq = []
    described_class.before_reset { seq << :before }
    described_class.after_reset { seq << :after }
    described_class.fetch(:z) { 1 }
    described_class.reset!
    expect(described_class.cached(:z)).to be_nil
    expect(seq).to eq(%i[before after])
  end

  it "skips cache when disabled" do
    n = 0
    described_class.disable!
    a = described_class.fetch(:q) { n += 1 }
    b = described_class.fetch(:q) { n += 1 }
    expect(n).to eq(2)
    expect(a).not_to eq(b)
  end
end
