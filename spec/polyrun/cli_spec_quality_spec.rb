require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe "polyrun spec-quality CLI" do
  it "merge-spec-quality and report-spec-quality" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        cov = File.join(dir, "coverage")
        FileUtils.mkdir_p(cov)
        frag = File.join(cov, "polyrun-spec-quality-fragment-0.jsonl")
        File.write(frag, <<~JSONL)
          {"example":"spec/a_spec.rb:1","unique_lines":0,"line_churn":0,"max_line_churn":0,"lines":[]}
          {"example":"spec/b_spec.rb:2","unique_lines":1,"line_churn":55,"max_line_churn":55,"lines":[["/lib/x.rb",1,55]]}
        JSONL

        out, st = polyrun("merge-spec-quality", "-o", "coverage/merged.json")
        expect(st.success?).to be true
        expect(out.strip).to end_with("coverage/merged.json")
        expect(JSON.parse(File.read("coverage/merged.json"))["examples"].size).to eq(2)

        report, st2 = polyrun("report-spec-quality", "-i", "coverage/merged.json", "--top", "5")
        expect(st2.success?).to be true
        expect(report).to include("Zero production lines")
        expect(report).to include("spec/a_spec.rb:1")
        expect(report).to include("spec/b_spec.rb:2")
      end
    end
  end
end
