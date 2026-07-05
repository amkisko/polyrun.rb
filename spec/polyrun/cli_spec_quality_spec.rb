require "spec_helper"
require "json"
require "fileutils"
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

  it "report-spec-quality --json and --strict exit 1 on gate failure" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        cfg = File.join(dir, "polyrun_spec_quality.yml")
        File.write(cfg, "max_zero_hit_examples: 0\nstrict: true\n")
        merged = File.join(dir, "merged.json")
        File.write(merged, JSON.dump({
          "examples" => {
            "spec/a_spec.rb:1" => {"unique_lines" => 0, "line_churn" => 0, "lines" => []}
          },
          "hot_lines" => {}
        }))
        out, st = polyrun("report-spec-quality", "-c", cfg, "-i", merged, "--json", "--strict", "--top", "1")
        expect(st.exitstatus).to eq(1)
        expect(out).to include('"zero_hit"')
        expect(out).to include("spec/a_spec.rb:1")
        expect(out).to include("polyrun spec-quality gate")
      end
    end
  end

  it "merge-spec-quality exits 2 without inputs when no fragments exist" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("coverage")
        out, st = polyrun("merge-spec-quality")
        expect(st.exitstatus).to eq(2)
        expect(out).to include("need -i FILE")
      end
    end
  end

  it "report-spec-quality writes to -o path" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        merged = File.join(dir, "merged.json")
        out_path = File.join(dir, "report.txt")
        File.write(merged, JSON.dump({"examples" => {}, "hot_lines" => {}}))
        out, st = polyrun("report-spec-quality", "-i", merged, "-o", out_path)
        expect(st.success?).to be true
        expect(out.strip).to eq(File.expand_path(out_path))
        expect(File.read(out_path)).to include("spec quality report")
      end
    end
  end

  it "merge-spec-quality accepts positional fragment paths" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        frag = File.join(dir, "frag.jsonl")
        File.write(frag, '{"example":"spec/a_spec.rb:1","unique_lines":0,"line_churn":0,"lines":[]}' + "\n")
        _out, st = polyrun("merge-spec-quality", "-o", "merged.json", frag)
        expect(st.success?).to be true
        expect(JSON.parse(File.read("merged.json"))["examples"]).not_to be_empty
      end
    end
  end

  it "report-spec-quality exits 2 without input file" do
    out, st = polyrun("report-spec-quality")
    expect(st.exitstatus).to eq(2)
    expect(out).to include("need -i FILE")
  end

  it "report-spec-quality accepts --plan shard manifests" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        merged = File.join(dir, "merged.json")
        plan0 = File.join(dir, "shard0.json")
        plan1 = File.join(dir, "shard1.json")
        cfg = File.join(dir, "polyrun_spec_quality.yml")
        File.write(cfg, "hot_line_example_overlap: 1\nmin_line_churn: 1\n")
        File.write(merged, JSON.dump({
          "examples" => {
            "spec/a_spec.rb:1" => {
              "unique_lines" => 1,
              "line_churn" => 1,
              "max_line_churn" => 1,
              "lines" => [],
              "profile" => {"wall" => 0.1}
            }
          },
          "hot_lines" => {
            "/lib/x.rb:1" => {"examples" => ["spec/a_spec.rb:1"], "example_count" => 12, "total_hits" => 50}
          }
        }))
        File.write(plan0, JSON.dump({"shard_index" => "0", "paths" => ["spec/a_spec.rb"]}))
        File.write(plan1, JSON.dump({"shard_index" => "1", "paths" => ["spec/b_spec.rb"]}))
        report, st = polyrun(
          "report-spec-quality",
          "-c", cfg,
          "-i", merged,
          "--plan", plan0,
          "--plan", plan1,
          "--top", "3"
        )
        expect(st.success?).to be true
        text = report.dup.force_encoding(Encoding::UTF_8)
        text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless text.valid_encoding?
        expect(text).to include("Partition hints")
      end
    end
  end

  it "report-spec-quality uses config defaults when config file is unreadable" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        merged = File.join(dir, "merged.json")
        File.write(merged, JSON.dump({"examples" => {}, "hot_lines" => {}}))
        report, st = polyrun("report-spec-quality", "-c", "/no/such/polyrun_spec_quality.yml", "-i", merged)
        expect(st.success?).to be true
        expect(report).to include("spec quality report")
      end
    end
  end

  it "merge-spec-quality discovers default fragment glob" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        cov = File.join(dir, "coverage")
        FileUtils.mkdir_p(cov)
        frag = File.join(cov, "polyrun-spec-quality-fragment-0.jsonl")
        File.write(frag, '{"example":"spec/a_spec.rb:1","unique_lines":0,"line_churn":0,"lines":[]}' + "\n")
        _out, st = polyrun("merge-spec-quality", "-o", "merged.json")
        expect(st.success?).to be true
        expect(File.read("merged.json")).to include("spec/a_spec.rb:1")
      end
    end
  end
end
