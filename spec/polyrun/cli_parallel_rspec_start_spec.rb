require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "run-shards --merge-coverage merges fragments after success" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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
      Dir.chdir(dir) do
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
      Dir.chdir(dir) do
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

  it "start runs script/build_spec_paths.rb when present" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
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

  it "start runs prepare before workers when prepare recipe is shell" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: touch ran_prepare
          partition:
            shard_total: 1
            paths_file: spec/paths.txt
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/paths.txt", "spec/a_spec.rb\n")
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
          "start", "--workers", "1", "-c", "polyrun.yml", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "ran_prepare"))).to be true
      end
    end
  end

  it "start skips auto-prepare when POLYRUN_START_SKIP_PREPARE=1" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: touch ran_prepare
          partition:
            shard_total: 1
            paths_file: spec/paths.txt
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/paths.txt", "spec/a_spec.rb\n")
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
        env = {"POLYRUN_START_SKIP_PREPARE" => "1", "RUBYOPT" => nil}
        root = File.expand_path("../..", __dir__)
        bin = File.join(root, "bin", "polyrun")
        _out, status = Open3.capture2e(env, "ruby", bin, "start", "--workers", "1", "-c", "polyrun.yml", "--", RbConfig.ruby, stub)
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "ran_prepare"))).to be false
      end
    end
  end

  it "start skips script/build_spec_paths.rb when POLYRUN_SKIP_BUILD_SPEC_PATHS=1" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("script")
        File.write("script/build_spec_paths.rb", "File.write(File.join(Dir.pwd, 'build_ran'), 'bad')\nexit 1\n")
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
        env = {"POLYRUN_SKIP_BUILD_SPEC_PATHS" => "1", "RUBYOPT" => nil}
        root = File.expand_path("../..", __dir__)
        bin = File.join(root, "bin", "polyrun")
        _out, status = Open3.capture2e(env, "ruby", bin, "start", "--workers", "1", "--", RbConfig.ruby, stub)
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "build_ran"))).to be false
      end
    end
  end
end
