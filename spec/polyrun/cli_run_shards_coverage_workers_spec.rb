require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "run-shards --merge-coverage fails when merged coverage is below config minimum_line_percent" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("config")
        File.write("config/polyrun_coverage.yml", "minimum_line_percent: 99\n")
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          frag = {"coverage" => {"/x.rb" => {"lines" => [nil, 1, 0]}}}
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump(frag))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        out, status = polyrun(
          "run-shards", "--workers", "1", "--merge-coverage", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be false
        expect(out.encode("UTF-8", invalid: :replace)).to include("below minimum").and include("(merged).")
      end
    end
  end

  it "run-shards --merge-coverage does not enforce minimum when strict is false in polyrun_coverage.yml" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("config")
        File.write("config/polyrun_coverage.yml", <<~YAML)
          minimum_line_percent: 99
          strict: false
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          require "fileutils"
          require "json"
          FileUtils.mkdir_p("coverage")
          idx = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
          frag = {"coverage" => {"/x.rb" => {"lines" => [nil, 1, 0]}}}
          File.write(File.join("coverage", "polyrun-fragment-\#{idx}.json"), JSON.dump(frag))
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        _, status = polyrun(
          "run-shards", "--workers", "1", "--merge-coverage", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
      end
    end
  end

  it "run-shards spawns parallel workers" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        File.write("spec/c_spec.rb", "")
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~RUBY)
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY
        out, status = polyrun(
          "run-shards", "--workers", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(out).to include("spec path(s) from")
        expect(out).to include("spec/**/*_spec.rb glob")
        expect(out).to include("parallel worker")
        expect(out).to include("pid=")
        expect(out).to include("interleaved")
        expect(out).to include("merge-coverage")
        expect(out).to include("polyrun-fragment")
      end
    end
  end

  it "run-shards merges polyrun.yml database URLs per shard" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: spec/paths.txt
            shard_total: 2
            shard_index: 0
          databases:
            template_db: app_template
            shard_db_pattern: "app_test_%{shard}"
            postgresql:
              host: localhost
              username: postgres
        YAML
        File.write("spec/paths.txt", "spec/a_spec.rb\nspec/b_spec.rb\n")
        stub = File.join(dir, "_child_env.rb")
        File.write(stub, <<~RUBY)
          db = ENV["DATABASE_URL"].to_s[%r{/([^/?]+)(\\?|$)}, 1]
          File.write(File.join(Dir.pwd, "seen-" + ENV["POLYRUN_SHARD_INDEX"] + ".txt"), db)
          exit 0
        RUBY
        _, status = polyrun(
          "-c", cfg,
          "run-shards", "--workers", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "seen-0.txt")).strip).to eq("app_test_0")
        expect(File.read(File.join(dir, "seen-1.txt")).strip).to eq("app_test_1")
      end
    end
  end
end
