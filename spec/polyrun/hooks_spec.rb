require "spec_helper"

RSpec.describe Polyrun::Hooks do
  describe ".parse_phase" do
    it "accepts RSpec-style names" do
      expect(described_class.parse_phase("before(:suite)")).to eq(:before_suite)
      expect(described_class.parse_phase("after(:each)")).to eq(:after_worker)
    end

    it "accepts snake_case" do
      expect(described_class.parse_phase("before_shard")).to eq(:before_shard)
    end

    it "returns nil for unknown phases" do
      expect(described_class.parse_phase("nope")).to be_nil
    end
  end

  describe ".suite_per_matrix_job?" do
    it "is true when POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB is truthy" do
      ENV["POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB"] = "1"
      expect(described_class.suite_per_matrix_job?).to be true
    end

    it "is false when unset" do
      expect(described_class.suite_per_matrix_job?).to be false
    end
  end

  describe "#run_phase_if_enabled" do
    it "returns 0 without running when POLYRUN_HOOKS_DISABLE=1" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          ENV["POLYRUN_HOOKS_DISABLE"] = "1"
          h = described_class.new("before_suite" => "printf x > skipped.txt")
          expect(h.run_phase_if_enabled(:before_suite, ENV.to_h)).to eq(0)
          expect(File.file?("skipped.txt")).to be false
        end
      end
    end
  end

  describe "#run_phase" do
    it "returns 1 when Ruby hook raises" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("bad.rb", "before(:suite) { raise \"boom\" }")
          h = described_class.new("ruby" => "bad.rb")
          expect(h.run_phase(:before_suite, ENV.to_h)).to eq(1)
        end
      end
    end

    it "runs shell commands from a YAML list in order" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          h = described_class.new(
            "before_suite" => ["printf a > order.txt", "printf b >> order.txt"]
          )
          expect(h.run_phase(:before_suite, ENV.to_h)).to eq(0)
          expect(File.read("order.txt")).to eq("ab")
        end
      end
    end
  end

  describe "#empty?" do
    it "is true when no hooks" do
      expect(described_class.new({}).empty?).to be true
    end

    it "is false when shell hook present" do
      expect(described_class.new("before_suite" => "true").empty?).to be false
    end
  end

  describe "#worker_hooks?" do
    it "is true when before_worker shell is present" do
      expect(described_class.new("before_worker" => "true").worker_hooks?).to be true
    end

    it "is true when Ruby DSL defines before(:each)" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("w.rb", "before(:each) { }")
          h = described_class.new("ruby" => "w.rb")
          expect(h.worker_hooks?).to be true
        end
      end
    end
  end

  describe "#merge_worker_ruby_env" do
    it "sets POLYRUN_HOOKS_RUBY_FILE when the file exists" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("h.rb", "before(:suite) { }")
          h = described_class.new("ruby" => "h.rb")
          out = h.merge_worker_ruby_env({})
          expect(File.realpath(out["POLYRUN_HOOKS_RUBY_FILE"])).to eq(File.realpath(File.join(dir, "h.rb")))
        end
      end
    end

    it "does not set POLYRUN_HOOKS_RUBY_FILE when the path is missing" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          h = described_class.new("ruby" => "missing.rb")
          expect(h.merge_worker_ruby_env({"FOO" => "1"})).to eq({"FOO" => "1"})
        end
      end
    end
  end

  describe "#build_worker_shell_script" do
    it "wraps main command with before/after worker hooks" do
      h = described_class.new(
        "before_worker" => "echo b",
        "after_worker" => "echo a"
      )
      script = h.build_worker_shell_script(%w[bundle exec rspec], %w[spec/x_spec.rb])
      expect(script).to include("echo b")
      expect(script).to include("bundle exec rspec spec/x_spec.rb")
      expect(script).to include("echo a")
      expect(script).to include("exit $ec")
    end
  end
end
