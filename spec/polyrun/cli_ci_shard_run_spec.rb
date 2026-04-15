require "spec_helper"
require "tmpdir"

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
end
