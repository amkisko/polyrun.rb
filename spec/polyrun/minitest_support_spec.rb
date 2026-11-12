require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe "polyrun/minitest_support" do
  it "loads without LoadError" do
    expect { require "polyrun/minitest_support" }.not_to raise_error
    expect(Polyrun::MinitestSupport).to be_a(Module)
  end

  it "does not load the minitest gem when only polyrun/minitest_support is required" do
    root = File.expand_path("../..", __dir__)
    lib = File.join(root, "lib")
    script = <<~RUBY
      require "polyrun/minitest_support"
      puts defined?(::Minitest::Test) ? "loaded" : "not_loaded"
    RUBY
    out, status = Open3.capture2e({"RUBYOPT" => nil}, RbConfig.ruby, "-I", lib, "-e", script, chdir: root)
    expect(status.success?).to be true
    expect(out.strip).to eq("not_loaded")
  end

  it "delegates install_parallel_provisioning! to ParallelProvisioning" do
    require "polyrun/minitest_support"

    called = false
    allow(Polyrun::Data::ParallelProvisioning).to receive(:run_suite_hooks!) do
      called = true
    end

    Polyrun::MinitestSupport.install_parallel_provisioning!
    expect(called).to be true
  end

  it "install_worker_ping! prepends when Minitest::Test is defined" do
    require "polyrun/minitest_support"
    stub_minitest = Module.new { const_set(:Test, Class.new) }
    stub_const("Minitest", stub_minitest)

    Polyrun::MinitestSupport.install_worker_ping!
    expect(Minitest::Test.ancestors).to include(Polyrun::MinitestSupport::WorkerPingTestHook)
  end

  it "install_spec_quality! delegates to MinitestHook" do
    require "polyrun/minitest_support"
    stub_minitest = Module.new { const_set(:Test, Class.new) }
    stub_const("Minitest", stub_minitest)
    ENV["POLYRUN_SPEC_QUALITY"] = "1"

    Polyrun::MinitestSupport.install_spec_quality!(only_if: -> { true }, root: Dir.mktmpdir)
    expect(Minitest::Test.ancestors).to include(Polyrun::SpecQuality::MinitestHook::SpecQualityTestHook)
  end

  it "install_spec_quality! no-ops when predicate is false" do
    require "polyrun/minitest_support"
    stub_minitest = Module.new { const_set(:Test, Class.new) }
    stub_const("Minitest", stub_minitest)

    Polyrun::MinitestSupport.install_spec_quality!(only_if: -> { false })
    expect(Minitest::Test.ancestors).not_to include(Polyrun::SpecQuality::MinitestHook::SpecQualityTestHook)
  end

  it "install_worker_ping! warns when Minitest::Test is not defined" do
    require "polyrun/minitest_support"
    hide_const("Minitest") if defined?(Minitest)

    expect(Polyrun::Log).to receive(:warn).with(/skipped/)
    Polyrun::MinitestSupport.install_worker_ping!
  end

  it "WorkerPingTestHook pings around setup and teardown" do
    require "polyrun/minitest_support"
    require "polyrun/worker_ping"

    base = Class.new do
      def setup
      end

      def teardown
      end
    end
    test_class = Class.new(base) do
      prepend Polyrun::MinitestSupport::WorkerPingTestHook

      def name
        "test_ping"
      end

      def method(_name)
        self
      end

      def source_location
        [__FILE__, __LINE__]
      end
    end

    instance = test_class.new
    allow(Polyrun::WorkerPing).to receive(:ping!)
    instance.setup
    instance.teardown
    expect(Polyrun::WorkerPing).to have_received(:ping!).with(location: kind_of(String)).twice
  end
end
