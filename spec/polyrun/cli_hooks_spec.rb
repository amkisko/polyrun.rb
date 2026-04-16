require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe "polyrun hook" do
  it "runs a phase from polyrun.yml" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          hooks:
            before_suite: 'printf x > hook_out.txt'
        YAML
        _out, status = polyrun("hook", "run", "before_suite")
        expect(status.success?).to be true
        expect(File.read("hook_out.txt")).to eq("x")
      end
    end
  end

  it "fails on unknown phase" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", "hooks: {}\n")
        _out, status = polyrun("hook", "run", "not_a_phase")
        expect(status.exitstatus).to eq(2)
      end
    end
  end

  it "run-shards invokes before_suite hook" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("polyrun.yml", <<~YAML)
          hooks:
            before_suite: 'printf ok > suite_hook.txt'
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "ARGV.each { |f| abort unless File.file?(f) }; exit 0\n")
        _out, status = polyrun(
          "run-shards", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read("suite_hook.txt")).to eq("ok")
      end
    end
  end

  it "hook run passes POLYRUN_SHARD_INDEX and POLYRUN_SHARD_TOTAL from flags" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          hooks:
            before_suite: 'printf "%s %s" "$POLYRUN_SHARD_INDEX" "$POLYRUN_SHARD_TOTAL" > hook_env.txt'
        YAML
        _out, status = polyrun("hook", "run", "before_suite", "--shard", "2", "--total", "8")
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "hook_env.txt"))).to eq("2 8")
      end
    end
  end

  it "run-shards skips hooks when POLYRUN_HOOKS_DISABLE=1" do
    ENV["POLYRUN_HOOKS_DISABLE"] = "1"
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("polyrun.yml", <<~YAML)
          hooks:
            before_suite: 'printf ok > suite_hook.txt'
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _out, status = polyrun(
          "run-shards", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "suite_hook.txt"))).to be false
      end
    end
  end

  it "run-shards runs before_shard for each worker in shard index order" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\n")
        %w[a.rb b.rb].each { |f| File.write(File.join(dir, f), "") }
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_shard: 'printf "${POLYRUN_SHARD_INDEX}" >> shard_seq.txt; echo >> shard_seq.txt'
          partition:
            paths_file: #{list}
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _out, status = polyrun(
          "-c", cfg,
          "run-shards", "--workers", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "shard_seq.txt")).split).to eq(%w[0 1])
      end
    end
  end
end
