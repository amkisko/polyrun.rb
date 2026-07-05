require "spec_helper"
require "polyrun/spec_quality/merge"

RSpec.describe Polyrun::SpecQuality::Merge do
  it "merges JSONL fragments and aggregates hot lines" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.jsonl")
      b = File.join(dir, "b.jsonl")
      File.write(a, <<~JSONL)
        {"example":"spec/a_spec.rb:1","unique_lines":1,"line_churn":2,"max_line_churn":2,"lines":[["/lib/x.rb",10,2]]}
      JSONL
      File.write(b, <<~JSONL)
        {"example":"spec/b_spec.rb:3","unique_lines":1,"line_churn":1,"max_line_churn":1,"lines":[["/lib/x.rb",10,1]]}
      JSONL

      merged = described_class.merge_files([a, b])
      expect(merged["examples"].size).to eq(2)
      hot = merged["hot_lines"]["/lib/x.rb:10"]
      expect(hot["example_count"]).to eq(2)
      expect(hot["total_hits"]).to eq(3)
    end
  end

  it "merge_and_write writes pretty JSON" do
    Dir.mktmpdir do |dir|
      frag = File.join(dir, "f.jsonl")
      out = File.join(dir, "merged.json")
      File.write(frag, '{"example":"spec/a_spec.rb:1","unique_lines":1,"lines":[]}' + "\n")
      described_class.merge_and_write([frag], out)
      parsed = JSON.parse(File.read(out))
      expect(parsed["examples"].size).to eq(1)
    end
  end
end
