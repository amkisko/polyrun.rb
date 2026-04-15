require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "queue init shard 1 is disjoint from shard 0 for the same paths file" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\nd.rb\n")
        _, st0 = polyrun("queue", "init", "--paths-file", list, "--shard", "0", "--total", "2", "--dir", ".q0")
        _, st1 = polyrun("queue", "init", "--paths-file", list, "--shard", "1", "--total", "2", "--dir", ".q1")
        expect(st0.success?).to be true
        expect(st1.success?).to be true
        out0, = polyrun("queue", "claim", "--dir", ".q0", "--batch", "10")
        out1, = polyrun("queue", "claim", "--dir", ".q1", "--batch", "10")
        c0 = JSON.parse(out0)["paths"]
        c1 = JSON.parse(out1)["paths"]
        expect(c0 & c1).to be_empty
        expect((c0 | c1).size).to eq(4)
      end
    end
  end

  it "queue init applies the same shard slice as plan when --shard and --total are set" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\nd.rb\n")
        out_init, st_init = polyrun(
          "queue", "init",
          "--paths-file", list,
          "--shard", "0",
          "--total", "2",
          "--dir", ".polyrun-queue"
        )
        expect(st_init.success?).to be true
        expect(JSON.parse(out_init)["count"]).to eq(2)
        out_claim, st_claim = polyrun("queue", "claim", "--dir", ".polyrun-queue", "--batch", "1")
        expect(st_claim.success?).to be true
        first = JSON.parse(out_claim)["paths"].first
        expect(first).to end_with("a.rb")
        out_claim2, st2 = polyrun("queue", "claim", "--dir", ".polyrun-queue", "--batch", "1")
        expect(st2.success?).to be true
        expect(JSON.parse(out_claim2)["paths"].first).to end_with("c.rb")
      end
    end
  end

  it "queue init orders by example weights when --timing-granularity example" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        ra = File.join(dir, "a.rb")
        rb = File.join(dir, "b.rb")
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "#{ra}:1\n#{rb}:2\n")
        timing = File.join(dir, "t.json")
        File.write(timing, JSON.dump({"#{ra}:1" => 1.0, "#{rb}:2" => 9.0}))
        _out_init, st_init = polyrun(
          "queue", "init",
          "--paths-file", list,
          "--timing", timing,
          "--timing-granularity", "example",
          "--dir", ".polyrun-queue"
        )
        expect(st_init.success?).to be true
        out_claim, st_claim = polyrun("queue", "claim", "--dir", ".polyrun-queue", "--batch", "1")
        expect(st_claim.success?).to be true
        claim = JSON.parse(out_claim)
        expect(claim["paths"].first).to end_with("b.rb:2")
      end
    end
  end

  it "queue init, claim, ack, and status via CLI" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\n")
        timing = File.join(dir, "t.json")
        File.write(timing, JSON.dump({"a.rb" => 3.0, "b.rb" => 1.0, "c.rb" => 1.0}))
        out_init, st_init = polyrun("queue", "init", "--paths-file", list, "--timing", timing, "--dir", ".polyrun-queue")
        expect(st_init.success?).to be true
        expect(JSON.parse(out_init)["count"]).to eq(3)

        out_claim, st_claim = polyrun("queue", "claim", "--dir", ".polyrun-queue", "--batch", "2")
        expect(st_claim.success?).to be true
        claim = JSON.parse(out_claim)
        expect(claim["paths"].size).to eq(2)
        lease = claim["lease_id"]

        out_stat, st_stat = polyrun("queue", "status", "--dir", ".polyrun-queue")
        expect(st_stat.success?).to be true
        expect(JSON.parse(out_stat)["pending"]).to eq(1)

        out_ack, st_ack = polyrun("queue", "ack", "--dir", ".polyrun-queue", "--lease", lease)
        expect(st_ack.success?).to be true
        expect(out_ack.strip).to eq("ok")

        out_stat2, st_stat2 = polyrun("queue", "status", "--dir", ".polyrun-queue")
        expect(st_stat2.success?).to be true
        s2 = JSON.parse(out_stat2)
        expect(s2["pending"]).to eq(1)
        expect(s2["done"]).to eq(2)
      end
    end
  end

  it "merge-timing merges fragment files" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "t0.json")
      b = File.join(dir, "t1.json")
      File.write(a, JSON.dump({"/a.rb" => 1.0, "/b.rb" => 2.0}))
      File.write(b, JSON.dump({"/a.rb" => 1.5, "/c.rb" => 0.5}))
      out = File.join(dir, "merged.json")
      _, status = polyrun("merge-timing", "-i", a, "-i", b, "-o", out)
      expect(status.success?).to be true
      m = JSON.parse(File.read(out))
      expect(m["/a.rb"]).to eq(1.5)
      expect(m["/b.rb"]).to eq(2.0)
    end
  end

  it "merge-timing exits 2 without inputs" do
    out, status = polyrun("merge-timing")
    expect(status.exitstatus).to eq(2)
    expect(out).to match(/need -i FILE/)
  end

  it "report-junit writes junit.xml next to RSpec JSON input" do
    Dir.mktmpdir do |dir|
      inp = File.join(dir, "rspec.json")
      File.write(inp, JSON.dump({
        "examples" => [
          {"description" => "x", "full_description" => "g x", "file_path" => "./a.rb", "status" => "passed", "run_time" => 0.01}
        ]
      }))
      out, status = polyrun("report-junit", "-i", inp)
      expect(status.success?).to be true
      junit_path = File.join(dir, "junit.xml")
      expect(out.strip).to eq(junit_path)
      expect(File.read(junit_path)).to include("<testsuites")
    end
  end

  it "report-timing prints slow files from merged timing JSON" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "polyrun_timing.json")
      File.write(f, JSON.dump({"/a.rb" => 2.0, "/b.rb" => 5.0}))
      out, status = polyrun("report-timing", "-i", f, "--top", "1")
      expect(status.success?).to be true
      expect(out).to include("/b.rb")
      expect(out).not_to include("/a.rb")
    end
  end

  it "merge-timing accepts positional file arguments" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "t.json")
      File.write(f, JSON.dump({"/a.rb" => 1.0}))
      out_path = File.join(dir, "merged.json")
      out, status = polyrun("merge-timing", f, "-o", out_path)
      expect(status.success?).to be true
      expect(JSON.parse(File.read(out_path))).to eq({"/a.rb" => 1.0})
      expect(out.strip).to eq(File.expand_path(out_path))
    end
  end
end
