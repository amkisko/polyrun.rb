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

  it "exits 2 when --shard-processes has no value" do
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
        out, status = polyrun("-c", cfg, "ci-shard-run", "--shard-processes", "--", "true")
        expect(status.exitstatus).to eq(2)
        expect(out).to match(/missing value for --shard-processes/)
      end
    end
  end

  it "caps --shard-processes at MAX_PARALLEL_WORKERS" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write(File.join(dir, "a.rb"), "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, "exit 0\n")
        over = Polyrun::Config::MAX_PARALLEL_WORKERS + 5
        out, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", over.to_s, "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(out).to include("capping")
        expect(out).to include(Polyrun::Config::MAX_PARALLEL_WORKERS.to_s)
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
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~'RUBY')
          require "json"
          File.write("argv.json", JSON.generate(ARGV))
          exit 0
        RUBY
        _, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard", "0", "--total", "2", "--",
          RbConfig.ruby, stub, "--format", "documentation"
        )
        expect(status.success?).to be true
        argv = JSON.parse(File.read(File.join(dir, "argv.json")))
        expect(argv).to eq(["--format", "documentation", "a.rb", "c.rb"])
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
        _out, status = polyrun("-c", cfg, "ci-shard-run", "--", "missing-binary-ci-shard")
        expect(status.success?).to be false
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
        stub = File.join(dir, "_argv.rb")
        File.write(stub, <<~'RUBY')
          require "json"
          File.write("argv.json", JSON.generate(ARGV))
          exit 0
        RUBY
        _, status = polyrun("-c", cfg, "ci-shard-run", "--", "#{RbConfig.ruby} #{stub}")
        expect(status.success?).to be true
        argv = JSON.parse(File.read(File.join(dir, "argv.json")))
        expect(argv).to eq(["x.rb"])
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

  it "omits POLYRUN_SHARD_MATRIX_* when only one local process runs" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\nb.rb\n")
        %w[a.rb b.rb].each { |f| File.write(File.join(dir, f), "") }
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~'RUBY')
          keys = %w[POLYRUN_SHARD_MATRIX_INDEX POLYRUN_SHARD_MATRIX_TOTAL]
          File.write("matrix.txt", keys.map { |k| ENV.key?(k) ? "yes" : "no" }.join(","))
          exit 0
        RUBY
        _, status = polyrun("-c", cfg, "ci-shard-run", "--", RbConfig.ruby, stub)
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "matrix.txt")).strip).to eq("no,no")
      end
    end
  end

  it "omits POLYRUN_SHARD_MATRIX_* when matrix has a single job" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "a.rb\n")
        File.write(File.join(dir, "a.rb"), "")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 1
            shard_index: 0
        YAML
        stub = File.join(dir, "_child.rb")
        File.write(stub, <<~'RUBY')
          keys = %w[POLYRUN_SHARD_MATRIX_INDEX POLYRUN_SHARD_MATRIX_TOTAL]
          File.write("matrix.txt", keys.map { |k| ENV.key?(k) ? "yes" : "no" }.join(","))
          exit 0
        RUBY
        _, status = polyrun(
          "-c", cfg,
          "ci-shard-run", "--shard-processes", "2", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.read(File.join(dir, "matrix.txt")).strip).to eq("no,no")
      end
    end
  end
end
# rubocop:enable Polyrun/FileLength
