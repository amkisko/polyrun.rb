require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe "polyrun/minitest" do
  it "loads without LoadError" do
    expect { require "polyrun/minitest" }.not_to raise_error
    expect(Polyrun::Minitest).to be_a(Module)
  end

  it "does not load the minitest gem when only polyrun/minitest is required" do
    root = File.expand_path("../..", __dir__)
    lib = File.join(root, "lib")
    script = <<~RUBY
      require "polyrun/minitest"
      puts defined?(::Minitest::Test) ? "loaded" : "not_loaded"
    RUBY
    out, status = Open3.capture2e({"RUBYOPT" => nil}, RbConfig.ruby, "-I", lib, "-e", script, chdir: root)
    expect(status.success?).to be true
    expect(out.strip).to eq("not_loaded")
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
