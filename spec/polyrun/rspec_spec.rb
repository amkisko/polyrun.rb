require "spec_helper"

RSpec.describe "polyrun/rspec" do
  it "loads without LoadError (regression: require path is ../polyrun)" do
    expect { require "polyrun/rspec" }.not_to raise_error
    expect(Polyrun::RSpec).to be_a(Module)
  end
end
