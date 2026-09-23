require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe "Polyrun::CLI suite and paths alignment" do
  it "bare polyrun selects minitest when paths_file lists tests even if spec/ exists" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        FileUtils.mkdir_p("test")
        File.write("spec/a_spec.rb", "")
        File.write("test/b_test.rb", "")
        File.write("test/paths.txt", "test/b_test.rb\n")
        File.write("polyrun.yml", <<~YAML)
          partition:
            suite: auto
            paths_file: test/paths.txt
        YAML

        out, _status = polyrun("-v")
        expect(out).to include("parallel minitest")
      end
    end
  end

  it "bare polyrun fails when partition.suite disagrees with paths_file" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("test")
        File.write("test/b_test.rb", "")
        File.write("test/paths.txt", "test/b_test.rb\n")
        File.write("polyrun.yml", <<~YAML)
          partition:
            suite: rspec
            paths_file: test/paths.txt
        YAML

        out, status = polyrun
        expect(status.exitstatus).to eq(2)
        expect(out).to match(/partition\.suite|paths_file|mismatch|disagree/i)
      end
    end
  end

  it "run-shards exits 2 when paths infer minitest but command is rspec" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("test")
        File.write("test/b_test.rb", "")
        list = File.join(dir, "paths.txt")
        File.write(list, "test/b_test.rb\n")

        out, status = polyrun(
          "run-shards", "--workers", "1", "--paths-file", list, "--",
          "bundle", "exec", "rspec"
        )
        expect(status.exitstatus).to eq(2)
        expect(out).to include("minitest")
        expect(out).to include("rspec")
      end
    end
  end

  it "parallel-minitest runs with an explicit worker command" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("test")
        File.write("test/b_test.rb", "")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          ARGV.each { |f| abort("missing \#{f}") unless File.file?(f) }
          exit 0
        RUBY

        _out, status = polyrun(
          "parallel-minitest", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
      end
    end
  end

  it "parallel-quick is a known subcommand" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec/polyrun_quick")
        File.write("spec/polyrun_quick/a.rb", "describe('x') { it('y') {} }\n")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, "exit 0\n")

        _out, status = polyrun(
          "parallel-quick", "--workers", "1", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
      end
    end
  end
end
