require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "emits plan manifest" do
    out, status = polyrun("plan", "--total", "2", "--shard", "0", "a.rb", "b.rb", "c.rb")
    expect(status.success?).to be true
    j = parse_polyrun_json(out)
    expect(j["paths"]).to eq(%w[a.rb c.rb])
  end

  it "plan with --timing-granularity example uses path:line costs and emits timing_granularity" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        ra = File.join(dir, "a.rb")
        rb = File.join(dir, "b.rb")
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "#{ra}:1\n#{rb}:2\n")
        timing = File.join(dir, "t.json")
        File.write(timing, JSON.dump({"#{ra}:1" => 10.0, "#{rb}:2" => 4.0}))
        out, status = polyrun(
          "plan",
          "--total", "2",
          "--shard", "0",
          "--timing", timing,
          "--paths-file", list,
          "--timing-granularity", "example",
          "--strategy", "cost_binpack"
        )
        expect(status.success?).to be true
        j = parse_polyrun_json(out)
        expect(j["strategy"]).to eq("cost_binpack")
        expect(j["timing_granularity"]).to eq("example")
        expect(j["shard_seconds"]).to eq([10.0, 4.0])
        want = Polyrun::Partition::TimingKeys.normalize_locator("#{ra}:1", Dir.pwd, :example)
        expect(j["paths"]).to eq([want])
      end
    end
  end

  it "plan with --timing uses cost_binpack and shard_seconds" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\n")
        timing = File.join(dir, "t.json")
        File.write(timing, JSON.dump({"a.rb" => 10.0, "b.rb" => 4.0, "c.rb" => 4.0}))
        out, status = polyrun("plan", "--total", "2", "--shard", "0", "--timing", timing, "--paths-file", list)
        expect(status.success?).to be true
        j = parse_polyrun_json(out)
        expect(j["strategy"]).to eq("cost_binpack")
        expect(j["shard_seconds"]).to eq([10.0, 8.0])
        expect(j["paths"]).to eq(["a.rb"])
      end
    end
  end

  it "plan uses partition.paths_file from config" do
    Dir.mktmpdir do |dir|
      list = File.join(dir, "specs.txt")
      File.write(list, "a.rb\nb.rb\nc.rb\n")
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        partition:
          paths_file: #{list}
          shard_total: 2
          shard_index: 0
      YAML
      out, status = polyrun("-c", cfg, "plan", "--shard", "0", "--total", "2")
      expect(status.success?).to be true
      expect(parse_polyrun_json(out)["paths"]).to eq(%w[a.rb c.rb])
    end
  end

  it "plan exits 2 when no paths and no paths_file" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        _out, status = polyrun("plan", "--shard", "0", "--total", "1")
        expect(status.exitstatus).to eq(2)
      end
    end
  end

  it "plan uses partition.timing_granularity from config when CLI omits flag" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        ra = File.join(dir, "a.rb")
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "#{ra}:1\n")
        timing = File.join(dir, "t.json")
        File.write(timing, JSON.dump({"#{ra}:1" => 1.0}))
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            timing_granularity: example
            shard_total: 1
            shard_index: 0
        YAML
        out, status = polyrun("-c", cfg, "plan", "--shard", "0", "--total", "1", "--timing", timing)
        expect(status.success?).to be true
        expect(parse_polyrun_json(out)["timing_granularity"]).to eq("example")
      end
    end
  end

  it "plan prefers --timing-granularity over POLYRUN_TIMING_GRANULARITY" do
    old = ENV["POLYRUN_TIMING_GRANULARITY"]
    ENV["POLYRUN_TIMING_GRANULARITY"] = "example"
    begin
      out, status = polyrun("plan", "--total", "1", "--shard", "0", "--timing-granularity", "file", "a.rb")
      expect(status.success?).to be true
      expect(parse_polyrun_json(out)).not_to have_key("timing_granularity")
    ensure
      if old.nil?
        ENV.delete("POLYRUN_TIMING_GRANULARITY")
      else
        ENV["POLYRUN_TIMING_GRANULARITY"] = old
      end
    end
  end

  it "plan emits identical JSON for repeated invocations with the same argv" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "specs.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        out1, status1 = polyrun("-c", cfg, "plan", "--shard", "0", "--total", "2")
        out2, status2 = polyrun("-c", cfg, "plan", "--shard", "0", "--total", "2")
        expect(status1.success?).to be true
        expect(status2.success?).to be true
        expect(out1).to eq(out2)
        expect(parse_polyrun_json(out1)["paths"]).to eq(%w[a.rb c.rb])
      end
    end
  end
end
