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

  it "runs bundle exec rspec with optional flags after --" do
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
        out, status = polyrun(
          "-c", cfg,
          "ci-shard-rspec", "--shard", "0", "--total", "2", "--", "--version"
        )
        expect(status.success?).to be true
        expect(out).to match(/RSpec/i)
      end
    end
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
        out, status = polyrun("-c", cfg, "ci-shard-rspec", "--shard-processes", "bad")
        expect(status.exitstatus).to eq(2)
        expect(out).to match(/must be an integer/)
      end
    end
  end

  it "fans out when --shard-processes > 1" do
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
        out, status = polyrun(
          "-c", cfg,
          "ci-shard-rspec", "--shard-processes", "2", "--shard", "0", "--total", "2", "--", "--version"
        )
        expect(status.success?).to be true
        expect(out).to include("NxM")
      end
    end
  end

  it "uses partition shard fields when plan argv after -- is only RSpec flags" do
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
        out, status = polyrun("-c", cfg, "ci-shard-rspec", "--", "--version")
        expect(status.success?).to be true
        expect(out).to match(/RSpec/i)
      end
    end
  end
end
