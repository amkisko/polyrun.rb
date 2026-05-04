require "spec_helper"
require "fileutils"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "run-shards --worker-timeout stops a stuck worker (exit 124) and reports shard" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~RUBY)
          if ENV["POLYRUN_SHARD_INDEX"] == "0"
            sleep 300
          else
            ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
            exit 0
          end
        RUBY
        out, status = polyrun(
          "run-shards", "--workers", "2", "--worker-timeout", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be false
        expect(out).to include("WORKER TIMEOUT").and include("shard 0").and include("exit 124")
      end
    end
  end

  it "run-shards --worker-idle-timeout stops when worker ping timestamp goes stale (exit 125)" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~RUBY)
          path = ENV.fetch("POLYRUN_WORKER_PING_FILE")
          File.binwrite(path, Process.clock_gettime(Process::CLOCK_MONOTONIC).to_s + "\\n" + "fake_spec.rb:42")
          sleep 300
        RUBY
        out, status = polyrun(
          "run-shards", "--workers", "1", "--worker-idle-timeout", "2", "--worker-timeout", "400", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be false
        expect(out).to include("WORKER IDLE TIMEOUT").and include("exit 125").and include("fake_spec.rb:42")
      end
    end
  end

  it "run-shards --worker-idle-timeout applies while another shard is still busy (polls every worker)" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~RUBY)
          shard = ENV.fetch("POLYRUN_SHARD_INDEX")
          case shard
          when "0"
            sleep 300
          when "1"
            path = ENV.fetch("POLYRUN_WORKER_PING_FILE")
            File.binwrite(path, Process.clock_gettime(Process::CLOCK_MONOTONIC).to_s + "\\n" + "fake_spec.rb:99")
            sleep 300
          else
            abort("unexpected shard \#{shard}")
          end
        RUBY
        out, status = polyrun(
          "run-shards", "--workers", "2", "--worker-idle-timeout", "2", "--worker-timeout", "400", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be false
        expect(out).to include("WORKER IDLE TIMEOUT").and include("shard 1").and include("fake_spec.rb:99")
      end
    end
  end
end
