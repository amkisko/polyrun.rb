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
    j = JSON.parse(out)
    expect(j["paths"]).to eq(%w[a.rb c.rb])
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
        j = JSON.parse(out)
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
      expect(JSON.parse(out)["paths"]).to eq(%w[a.rb c.rb])
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
end
