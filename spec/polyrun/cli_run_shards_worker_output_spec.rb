require "spec_helper"
require "fileutils"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "run-shards with worker output routing writes stdout and stderr to shard logs" do
    Dir.mktmpdir do |directory|
      with_chdir(directory) do
        log_directory = File.join(directory, "worker-logs")
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        stub = File.join(directory, "_child.rb")
        File.write(stub, <<~RUBY)
          $stdout.puts "stdout-marker"
          $stderr.puts "stderr-marker"
          ARGV.each { |file| abort("missing \#{file}") unless File.file?(file) }
          exit 0
        RUBY
        out, status = polyrun(
          "run-shards", "--workers", "2", "--",
          RbConfig.ruby, stub,
          env: {
            "POLYRUN_WORKER_OUTPUT_ROUTING" => "1",
            "POLYRUN_WORKER_LOG_DIR" => log_directory,
            "POLYRUN_WORKER_OUTPUT_PREFIX" => "0"
          }
        )
        expect(status.success?).to be(true)
        expect(out).to include("shard 0 log").and include("shard 1 log")
        expect(File.read(File.join(log_directory, "shard-0.log"))).to include("stdout-marker")
        expect(File.read(File.join(log_directory, "shard-1.log"))).to include("stderr-marker")
      end
    end
  end
end
