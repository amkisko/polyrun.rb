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
        Coverage.start(lines: true)
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
end
