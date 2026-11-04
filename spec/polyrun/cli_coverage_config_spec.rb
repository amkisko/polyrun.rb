require "spec_helper"
require "fileutils"
require "json"
require "rbconfig"

RSpec.describe "coverage from the active config", :aggregate_failures do
  %w[run-shards ci-shard-run].each do |command|
    it "passes --config through to coverage resolution in #{command} child workers" do
      library = File.expand_path("../../lib", __dir__)
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          FileUtils.mkdir_p("spec")
          File.write("spec/a_spec.rb", "")
          File.write("polyrun.yml", "coverage:\n  minimum_line_percent: 10\n")
          File.write("spec/paths.txt", "spec/a_spec.rb\n")
          File.write("selected.yml", "partition:\n  paths_file: spec/paths.txt\ncoverage:\n  minimum_line_percent: 90\n")
          script = <<~RUBY
            require "polyrun/coverage/config_resolve"
            cfg = Polyrun::Coverage::ConfigResolve.load(root: Dir.pwd)
            File.write("worker-minimum", cfg.fetch("minimum_line_percent"))
          RUBY

          _out, status = polyrun(
            "--config", "selected.yml", command, "--workers", "1", "--",
            RbConfig.ruby, "-I", library, "-e", script, in_process: false
          )

          expect(status.success?).to be true
          expect(File.read("worker-minimum")).to eq("90")
        end
      end
    end
  end

  it "enforces the inline minimum from --config after merging workers" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p(%w[spec coverage])
        File.write("spec/a_spec.rb", "")
        File.write("polyrun.yml", "coverage:\n  minimum_line_percent: 0\n")
        File.write("selected.yml", "coverage:\n  minimum_line_percent: 99\n")
        File.write("coverage/polyrun-fragment-0.json", JSON.generate(
          "coverage" => {"/x.rb" => {"lines" => [1, 0]}}
        ))

        out, status = polyrun(
          "--config", "selected.yml", "run-shards", "--workers", "1",
          "--merge-coverage", "--merge-format", "json", "--", RbConfig.ruby, "-e", "exit 0"
        )

        expect(status.exitstatus).to eq(1)
        expect(out).to include("below minimum")
      end
    end
  end
end
