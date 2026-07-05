# rubocop:disable Polyrun/FileLength -- start prepare and worker bootstrap integration cases
require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "start runs prepare before workers when prepare recipe is shell" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
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
      with_chdir(dir) do
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
      with_chdir(dir) do
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

  it "start passes --workers count to shard children" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          partition:
            shard_total: 1
            paths_file: spec/paths.txt
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/paths.txt", "spec/a_spec.rb\nspec/b_spec.rb\n")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump({"coverage" => {"/y.rb" => {"lines" => [nil, 2]}}}))
          File.write("workers.txt", ENV.fetch("POLYRUN_SHARD_TOTAL", "?"))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        _, status = polyrun("start", "--workers", "3", "-c", "polyrun.yml", "--", RbConfig.ruby, stub)
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "workers.txt"))).to eq("3")
      end
    end
  end

  it "start clamps --workers to MAX_PARALLEL_WORKERS" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
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
          File.write("workers.txt", ENV.fetch("POLYRUN_SHARD_TOTAL", "?"))
          exit 0
        RUBY
        _, status = polyrun(
          "start", "--workers", (Polyrun::Config::MAX_PARALLEL_WORKERS + 5).to_s,
          "-c", "polyrun.yml", "--", RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "workers.txt"))).to eq(Polyrun::Config::MAX_PARALLEL_WORKERS.to_s)
      end
    end
  end

  it "start uses POLYRUN_WORKERS when --workers is omitted" do
    old = ENV["POLYRUN_WORKERS"]
    ENV["POLYRUN_WORKERS"] = "4"
    begin
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          File.write("polyrun.yml", <<~YAML)
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
            File.write("workers.txt", ENV.fetch("POLYRUN_SHARD_TOTAL", "?"))
            exit 0
          RUBY
          _, status = polyrun("start", "-c", "polyrun.yml", "--", RbConfig.ruby, stub)
          expect(status.success?).to be true
          expect(File.read(File.join(dir, "workers.txt"))).to eq("4")
        end
      end
    ensure
      old ? ENV.store("POLYRUN_WORKERS", old) : ENV.delete("POLYRUN_WORKERS")
    end
  end

  it "start skips auto-prepare when prepare recipe has no side effects" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: default
          partition:
            shard_total: 1
            paths_file: spec/paths.txt
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/paths.txt", "spec/a_spec.rb\n")
        File.write("spec/a_spec.rb", "")
        File.write("ran_prepare", "should_not_run") if File.file?("ran_prepare")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump({"coverage" => {"/y.rb" => {"lines" => [nil, 2]}}}))
          exit 0
        RUBY
        _, status = polyrun("start", "--workers", "1", "-c", "polyrun.yml", "--", RbConfig.ruby, stub)
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "ran_prepare"))).to be false
      end
    end
  end

  it "start skips database provision when start.databases is false" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          start:
            databases: false
          databases:
            template_db: would_fail_if_provisioned
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
          exit 0
        RUBY
        _, status = polyrun("start", "--workers", "1", "-c", "polyrun.yml", "--", RbConfig.ruby, stub)
        expect(status.success?).to be true
      end
    end
  end
end
# rubocop:enable Polyrun/FileLength
