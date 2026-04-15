require "spec_helper"
require "tmpdir"

RSpec.describe "Polyrun::CLI ci-shard-rspec" do
  it "exits 2 when the shard has no paths" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        list = File.join(dir, "spec_paths.txt")
        File.write(list, "only.rb\n")
        cfg = File.join(dir, "polyrun.yml")
        File.write(cfg, <<~YAML)
          partition:
            paths_file: #{list}
            shard_total: 2
            shard_index: 0
        YAML
        out, status = polyrun("-c", cfg, "ci-shard-rspec", "--shard", "1", "--total", "2")
        expect(status.exitstatus).to eq(2)
        expect(out).to match(/no paths/)
      end
    end
  end

  it "execs bundle exec rspec with planned paths and optional rspec argv after --" do
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
          "bundle", "exec", "rspec", "--format", "documentation", "a.rb", "c.rb"
        )
        cli.send(:cmd_ci_shard_rspec, ["--shard", "0", "--total", "2", "--", "--format", "documentation"], cfg)
      end
    end
  end

  it "propagates Errno from exec when bundle is missing" do
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
        allow(cli).to receive(:exec).with("bundle", "exec", "rspec", "a.rb").and_raise(Errno::ENOENT.new("bundle"))
        expect { cli.send(:cmd_ci_shard_rspec, [], cfg) }.to raise_error(Errno::ENOENT)
        expect(cli).to have_received(:exec).with("bundle", "exec", "rspec", "a.rb")
      end
    end
  end

  it "with only -- and RSpec flags (empty plan argv), uses partition shard and passes flags before paths" do
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
          "bundle", "exec", "rspec", "--format", "documentation", "a.rb", "c.rb"
        )
        cli.send(:cmd_ci_shard_rspec, ["--", "--format", "documentation"], cfg)
      end
    end
  end
end
