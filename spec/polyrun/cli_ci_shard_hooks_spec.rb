require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe "Polyrun ci-shard hooks" do
  it "fanout exits 1 when a local worker fails" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\n")
        %w[a.rb b.rb].each { |f| File.write(File.join(dir, f), "") }
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit(ARGV.include?('b.rb') ? 1 : 0)\n")
        out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.exitstatus).to eq(1)
        expect(out).to include("some failed")
      end
    end
  end

  it "fanout returns before_suite hook failure code" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write("a.rb", "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_suite: 'exit 3'
          partition:
            paths_file: #{list}
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.exitstatus).to eq(3)
      end
    end
  end

  it "single-shard run runs hooks when configured" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write("a.rb", "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_shard: 'printf shard > hook.txt'
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
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read("hook.txt")).to eq("shard")
      end
    end
  end

  it "exits 2 when the shard plan has no paths" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        out, status = polyrun("-c", cfg, "ci-shard-run", "--shard", "9", "--total", "10", "--", "true")
        expect(status.exitstatus).to eq(2)
        expect(out).to include("no paths for this shard")
      end
    end
  end
end
