require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "run-shards --merge-coverage merges fragments after success" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump({"coverage" => {"/x.rb" => {"lines" => [nil, 1]}}}))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        _, status = polyrun(
          "run-shards", "--workers", "1", "--merge-coverage", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        merged = File.join(dir, "coverage", "merged.json")
        expect(File.file?(merged)).to be true
        j = JSON.parse(File.read(merged))
        expect(j["coverage"]["/x.rb"]["lines"]).to eq([nil, 1])
      end
    end
  end

  it "parallel-rspec is run-shards with merge-coverage and a default command" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump({"coverage" => {"/y.rb" => {"lines" => [nil, 2]}}}))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        _, status = polyrun(
          "parallel-rspec", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        merged = File.join(dir, "coverage", "merged.json")
        expect(File.file?(merged)).to be true
        j = JSON.parse(File.read(merged))
        expect(j["coverage"]["/y.rb"]["lines"]).to eq([nil, 2])
      end
    end
  end

  it "start is parallel-rspec with merge-coverage and a default command" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump({"coverage" => {"/y.rb" => {"lines" => [nil, 2]}}}))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        _, status = polyrun(
          "start", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        merged = File.join(dir, "coverage", "merged.json")
        expect(File.file?(merged)).to be true
        j = JSON.parse(File.read(merged))
        expect(j["coverage"]["/y.rb"]["lines"]).to eq([nil, 2])
      end
    end
  end

  it "run-shards --merge-failures merges fragments after shard failure" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          abort "expected POLYRUN_FAILURE_FRAGMENTS=1" unless ENV["POLYRUN_FAILURE_FRAGMENTS"] == "1"
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("tmp/polyrun_failures")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          path = File.join("tmp/polyrun_failures", "polyrun-failure-fragment-worker\#{idx}.jsonl")
          File.write(path, JSON.generate({"id" => "rspec_a", "message" => "failed here"}) + "\\n")
          exit 1
        RUBY
        _, status = polyrun(
          "run-shards", "--workers", "1", "--merge-failures", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be false
        merged = File.join(dir, "tmp", "polyrun_failures", "merged.jsonl")
        expect(File.file?(merged)).to be true
        line = File.read(merged).lines.first.strip
        expect(JSON.parse(line)["message"]).to eq("failed here")
      end
    end
  end

  it "merge-failures command writes json" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        f = File.join(dir, "f.jsonl")
        File.write(f, JSON.generate({"id" => "z", "message" => "m"}) + "\n")
        out = File.join(dir, "out.json")
        _, status = polyrun(
          "merge-failures", "-i", f, "-o", out, "--format", "json"
        )
        expect(status.success?).to be true
        expect(JSON.parse(File.read(out))["failures"].size).to eq(1)
      end
    end
  end

  it "merge-failures command exits 1 on invalid JSONL" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        f = File.join(dir, "bad.jsonl")
        File.write(f, "not json\n")
        _, status = polyrun(
          "merge-failures", "-i", f, "-o", File.join(dir, "out.jsonl"), "--format", "jsonl"
        )
        expect(status.success?).to be false
        expect(status.exitstatus).to eq(1)
      end
    end
  end

  it "start runs script/build_spec_paths.rb when present" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("script")
        File.write("script/build_spec_paths.rb", "File.write(File.join(Dir.pwd, 'build_ran'), 'ok')\n")
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump({"coverage" => {"/z.rb" => {"lines" => [nil, 3]}}}))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        _, status = polyrun(
          "start", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "build_ran"))).to eq("ok")
      end
    end
  end
end
