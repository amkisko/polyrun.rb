require "spec_helper"
require "polyrun/sus_support"

RSpec.describe Polyrun::SusSupport do
  describe ".install_parallel_provisioning!" do
    it "delegates to ParallelProvisioning.run_suite_hooks!" do
      expect(Polyrun::Data::ParallelProvisioning).to receive(:run_suite_hooks!)
      described_class.install_parallel_provisioning!
    end
  end

  describe ".install_coverage!" do
    around do |example|
      old_cov = ENV["POLYRUN_COVERAGE"]
      old_covered = ENV["COVERAGE"]
      old_dis = ENV["POLYRUN_COVERAGE_DISABLE"]
      example.run
      if old_cov
        ENV["POLYRUN_COVERAGE"] = old_cov
      else
        ENV.delete("POLYRUN_COVERAGE")
      end
      if old_covered
        ENV["COVERAGE"] = old_covered
      else
        ENV.delete("COVERAGE")
      end
      if old_dis
        ENV["POLYRUN_COVERAGE_DISABLE"] = old_dis
      else
        ENV.delete("POLYRUN_COVERAGE_DISABLE")
      end
    end

    it "starts the collector when COVERAGE is set" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      ENV["COVERAGE"] = "BriefSummary"
      expect(Polyrun::Coverage::Collector).to receive(:start!).with(hash_including(root: Dir.pwd))
      described_class.install_coverage!
    end

    it "no-ops when coverage is not requested" do
      ENV.delete("POLYRUN_COVERAGE")
      ENV.delete("COVERAGE")
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      expect(Polyrun::Coverage::Collector).not_to receive(:start!)
      described_class.install_coverage!
    end

    it "skips when Covered::Sus is already mixed into Sus::Config" do
      ENV["COVERAGE"] = "true"
      ENV.delete("POLYRUN_COVERAGE_DISABLE")
      covered_sus = Module.new
      sus_config = Class.new
      stub_const("Covered::Sus", covered_sus)
      stub_const("Sus::Config", sus_config)
      sus_config.include(covered_sus)
      expect(Polyrun::Coverage::Collector).not_to receive(:start!)
      expect(Polyrun::Log).to receive(:warn).with(/Covered::Sus/)
      described_class.install_coverage!
    end
  end

  describe ".install_worker_ping!" do
    it "warns and returns when Sus::Config is missing" do
      hide_const("Sus") if defined?(Sus)
      expect(Polyrun::Log).to receive(:warn).with(/install_worker_ping! skipped/)
      described_class.install_worker_ping!
    end
  end
end
