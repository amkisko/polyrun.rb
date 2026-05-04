# rubocop:disable Polyrun/FileLength -- exhaustive ci-shard-run integration cases
require "spec_helper"
require "tmpdir"
require "rbconfig"

RSpec.describe "Polyrun::CLI ci-shard-run" do
  it "exits 2 when -- is missing" do
    out, status = polyrun("ci-shard-run", "bundle", "exec", "rspec")
    expect(status.exitstatus).to eq(2)
    expect(out).to match(/need --/)
  end

  it "exits 2 when command after -- is empty" do
    out, status = polyrun("ci-shard-run", "--")
    expect(status.exitstatus).to eq(2)
    expect(out).to match(/empty command/)
  end

  it "exits 2 when --shard-processes is not an integer" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        out, status = polyrun("-c", cfg, "ci-shard-run", "--shard-processes", "x", "--", "true")
        expect(status.exitstatus).to eq(2)
        expect(out).to match(/must be an integer/)
      end
    end
  end

  it "execs user command with planned paths appended" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        cli = Polyrun::CLI.new
        expect(cli).to receive(:exec).with(
          "bundle", "exec", "polyrun", "quick", "--format", "documentation", "a.rb", "c.rb"
        )
        cli.send(
          :cmd_ci_shard_run,
          ["--shard", "0", "--total", "2", "--", "bundle", "exec", "polyrun", "quick", "--format", "documentation"],
          cfg
        )
      end
    end
  end

  it "propagates Errno from exec (e.g. missing executable)" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        cli = Polyrun::CLI.new
        allow(cli).to receive(:exec).with("missing-binary-ci-shard", "a.rb").and_raise(Errno::ENOENT.new("nope"))
        expect { cli.send(:cmd_ci_shard_run, ["--", "missing-binary-ci-shard"], cfg) }.to raise_error(Errno::ENOENT)
        expect(cli).to have_received(:exec).with("missing-binary-ci-shard", "a.rb")
      end
    end
  end

  it "splits a single-string command with Shellwords when it contains spaces" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "x.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        cli = Polyrun::CLI.new
        expect(cli).to receive(:exec).with("bundle", "exec", "ruby", "-Itest", "x.rb")
        cli.send(:cmd_ci_shard_run, ["--", "bundle exec ruby -Itest"], cfg)
      end
    end
  end

  it "skips suite hooks when shard_total > 1 (matrix); shard hooks still run" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write(File.join(dir, "a.rb"), "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_suite: 'printf suite > suite_before.txt'
            after_suite: 'printf suite > suite_after.txt'
            before_shard: 'printf shard > shard_before.txt'
            after_shard: 'printf shard > shard_after.txt'
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard", "0", "--total", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "suite_before.txt"))).to be false
        expect(File.file?(File.join(dir, "suite_after.txt"))).to be false
        expect(File.read(File.join(dir, "shard_before.txt"))).to eq("shard")
        expect(File.read(File.join(dir, "shard_after.txt"))).to eq("shard")
      end
    end
  end

  it "runs suite hooks for ci-shard-run when shard_total is 1" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write(File.join(dir, "a.rb"), "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          hooks:
            before_suite: 'printf suite > suite_before.txt'
            after_suite: 'printf suite > suite_after.txt'
            before_shard: 'printf shard > shard_before.txt'
            after_shard: 'printf shard > shard_after.txt'
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        _, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "suite_before.txt"))).to eq("suite")
        expect(File.read(File.join(dir, "suite_after.txt"))).to eq("suite")
        expect(File.read(File.join(dir, "shard_before.txt"))).to eq("shard")
        expect(File.read(File.join(dir, "shard_after.txt"))).to eq("shard")
      end
    end
  end

  it "runs suite hooks on each matrix job when POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1" do
    old = ENV["POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB"]
    ENV["POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB"] = "1"
    begin
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          list = File.join(dir, "spec_paths.txt")
          File.write(list, "a.rb\n")
          File.write(File.join(dir, "a.rb"), "")
          cfg = File.join(dir, "polyrun.yml")
          File.write(cfg, <<~YAML)
            hooks:
              before_suite: 'printf suite > suite_before.txt'
              after_suite: 'printf suite > suite_after.txt'
              before_shard: 'printf shard > shard_before.txt'
              after_shard: 'printf shard > shard_after.txt'
            partition:
              paths_file: #{list}
              shard_total: 2
              shard_index: 0
          YAML
          stub = File.join(dir, "_child.rb")
          File.write(stub, "exit 0\n")
          _, status = polyrun(
            "-c", cfg,
            "ci-shard-run", "--shard", "0", "--total", "2", "--",
            RbConfig.ruby, stub
          )
          expect(status.success?).to be true
          expect(File.read(File.join(dir, "suite_before.txt"))).to eq("suite")
          expect(File.read(File.join(dir, "suite_after.txt"))).to eq("suite")
        end
      end
    ensure
      if old.nil?
        ENV.delete("POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB")
      else
        ENV["POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB"] = old
      end
    end
  end

  it "fans out local processes when --shard-processes > 1" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\nd.rb\n")
        # Shard 0 of 2 gets a.rb and c.rb; child script checks files exist.
        %w[a.rb c.rb].each { |f| File.write(File.join(dir, f), "") }
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~'RUBY')
          ARGV.each { |f| abort("missing #{f}") unless File.file?(f) }
          exit 0
        RUBY
        out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(out).to include("NxM")
        expect(out).to include("pid=")
      end
    end
  end

  it "sets POLYRUN_SHARD_MATRIX_* in children when matrix has N>1 and M>1" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\nc.rb\nd.rb\n")
        # Shard 1 of 2 gets b.rb and d.rb.
        %w[b.rb d.rb].each { |f| File.write(File.join(dir, f), "") }
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 1
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~'RUBY')
          idx = ENV["POLYRUN_SHARD_INDEX"]
          File.write("seen-#{idx}.txt", [ENV["POLYRUN_SHARD_MATRIX_INDEX"], ENV["POLYRUN_SHARD_MATRIX_TOTAL"]].join(","))
          exit 0
        RUBY
        _, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "seen-0.txt")).strip).to eq("1,2")
        expect(File.read(File.join(dir, "seen-1.txt")).strip).to eq("1,2")
      end
    end
  end
end
# rubocop:enable Polyrun/FileLength
