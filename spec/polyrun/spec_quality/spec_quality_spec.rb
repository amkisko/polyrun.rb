require "spec_helper"
require "polyrun/spec_quality"

RSpec.describe Polyrun::SpecQuality do
  around do |ex|
    prev = ENV.to_h
    ENV.delete("POLYRUN_SPEC_QUALITY")
    ENV.delete("POLYRUN_SPEC_QUALITY_DISABLE")
    ex.run
  ensure
    ENV.replace(prev)
    described_class.instance_variable_set(:@config, nil) if described_class.instance_variable_defined?(:@config)
    described_class.instance_variable_set(:@current, nil) if described_class.instance_variable_defined?(:@current)
  end

  describe ".start! / finish_example!" do
    it "writes a JSONL row when coverage deltas exist" do
      skip "Coverage.peek_result unavailable" unless defined?(Coverage) && Coverage.respond_to?(:peek_result)

      Dir.mktmpdir do |dir|
        lib = File.join(dir, "lib")
        FileUtils.mkdir_p(lib)
        rb = File.join(lib, "sample.rb")
        File.write(rb, "def bump\n  1\nend\n")

        out = File.join(dir, "coverage", "frag.jsonl")
        Coverage.start(lines: true) unless Coverage.running?
        load rb
        described_class.start!(root: dir, output_path: out, sample: 1.0, track_under: %w[lib], profile: [])

        bump
        described_class.start_example!(location: "spec/x_spec.rb:1")
        bump
        bump
        row = described_class.finish_example!(location: "spec/x_spec.rb:1")

        expect(row["line_churn"]).to be >= 1
        expect(File).to exist(out)
        expect(File.read(out).lines.size).to eq(1)
      end
    end
  end

  describe ".pause" do
    it "skips finish when paused" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "q.jsonl")
        described_class.start!(root: dir, output_path: out, profile: [])
        described_class.start_example!(location: "spec/a_spec.rb:1")
        described_class.pause
        expect(described_class.finish_example!(location: "spec/a_spec.rb:1")).to be_nil
        expect(File.read(out)).to eq("")
      end
    end
  end

  describe ".record_sql! and helpers" do
    it "records sql when an example is active" do
      Dir.mktmpdir do |dir|
        described_class.start!(root: dir, output_path: File.join(dir, "q.jsonl"), profile: [], sql_counter: false)
        described_class.start_example!(location: "spec/a_spec.rb:1")
        described_class.record_sql!("SELECT 1")
        expect(described_class.instance_variable_get(:@current)[:sql_count]).to eq(1)
      end
    end

    it "spec_quality_requested_for_quick? reads env and config" do
      ENV["POLYRUN_SPEC_QUALITY"] = "1"
      expect(described_class.spec_quality_requested_for_quick?).to be true
    end

    it "skips ignored examples" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "q.jsonl")
        described_class.start!(root: dir, output_path: out, profile: [], sample: 1.0, ignore_examples: ["skip_me"])
        described_class.start_example!(location: "spec/skip_me_spec.rb:1")
        expect(described_class.finish_example!(location: "spec/skip_me_spec.rb:1")).to be_nil
      end
    end

    it "finish_example! returns nil for pending examples" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "q.jsonl")
        described_class.start!(root: dir, output_path: out, profile: [], sample: 1.0)
        described_class.start_example!(location: "spec/pending_spec.rb:1")
        expect(described_class.finish_example!(location: "spec/pending_spec.rb:1", pending: true)).to be_nil
      end
    end
  end
end
