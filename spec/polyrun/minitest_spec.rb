require "spec_helper"

RSpec.describe "polyrun/minitest" do
  it "loads without LoadError" do
    expect { require "polyrun/minitest" }.not_to raise_error
    expect(Polyrun::Minitest).to be_a(Module)
  end

  it "does not require minitest in source (opt-in integration only)" do
    path = File.expand_path("../../lib/polyrun/minitest.rb", __dir__)
    src = File.read(path)
    expect(src).not_to match(/require\s+["']minitest/)
  end

  it "delegates install_parallel_provisioning! to ParallelProvisioning" do
    require "polyrun/minitest"

    called = false
    allow(Polyrun::Data::ParallelProvisioning).to receive(:run_suite_hooks!) do
      called = true
    end

    Polyrun::Minitest.install_parallel_provisioning!
    expect(called).to be true
  end
end
