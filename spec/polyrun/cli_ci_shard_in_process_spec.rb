require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe "Polyrun ci-shard in-process coverage paths" do
  it "ci-shard-run single shard uses system when hooks are configured" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write("a.rb", "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_shard: 'printf before > shard_hook.txt'
            after_shard: 'printf after >> shard_hook.txt'
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--",
          RbConfig.ruby, stub,
          in_process: true
        )
        expect(status.success?).to be true
        expect(File.read("shard_hook.txt")).to eq("beforeafter")
      end
    end
  end

  it "ci-shard-rspec single shard runs with hooks without exec" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write("a.rb", "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_shard: 'printf ok > rspec_hook.txt'
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        _out, status = polyrun(
          "-c", cfg,
          "ci-shard-rspec", "--", "--version",
          in_process: true
        )
        expect(status.success?).to be true
        expect(File.read("rspec_hook.txt")).to eq("ok")
      end
    end
  end

  it "ci-shard-run fanout runs suite hooks and finishes workers" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\n")
        %w[a.rb b.rb].each { |f| File.write(f, "") }
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_suite: 'printf suite > suite.txt'
          partition:
            paths_file: #{list}
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", "2", "--",
          RbConfig.ruby, stub,
          in_process: true
        )
        expect(status.success?).to be true
        expect(File.read("suite.txt")).to eq("suite")
        expect(out).to include("finished 2 worker(s)")
      end
    end
  end

  it "ci-shard-run returns after_shard hook exit code" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write("a.rb", "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_shard: 'true'
            after_shard: 'exit 4'
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--",
          RbConfig.ruby, stub,
          in_process: true
        )
        expect(status.exitstatus).to eq(4)
      end
    end
  end
end
