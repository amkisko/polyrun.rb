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

  it "bare polyrun with suite minitest skips legacy spec/spec_paths.txt" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        FileUtils.mkdir_p("test")
        File.write("spec/a_spec.rb", "")
        File.write("spec/spec_paths.txt", "spec/a_spec.rb\n")
        File.write("test/a_test.rb", "")
        File.write("polyrun.yml", <<~YAML)
          partition:
            suite: minitest
        YAML
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          ARGV.each { |f| abort("unexpected \#{f}") unless f.end_with?("_test.rb") }
          exit 0
        RUBY

        out, status = polyrun(
          "run-shards", "--workers", "1", "-c", "polyrun.yml", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(out).to include("test")
        expect(out).not_to include("spec/spec_paths.txt")
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

  it "run-shards exits 2 when RSpec paths are paired with bin/rails test" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        list = File.join(dir, "paths.txt")
        File.write(list, "spec/a_spec.rb\n")

        out, status = polyrun(
          "run-shards", "--workers", "1", "--paths-file", list, "--",
          "bin/rails", "test"
        )
        expect(status.exitstatus).to eq(2)
        expect(out).to include("rspec")
        expect(out).to include("minitest")
      end
    end
  end

  it "run-shards does not treat path:line RSpec locators as Quick against rspec" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        list = File.join(dir, "paths.txt")
        File.write(list, "spec/a_spec.rb:1\n")

        out, _status = polyrun(
          "run-shards", "--workers", "1", "--paths-file", list, "--",
          "bundle", "exec", "rspec"
        )
        expect(out).not_to include("paths infer quick")
        expect(out).not_to include("but command looks like")
      end
    end
  end

  it "run-shards allows mixed lists for suite-agnostic custom runners" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        FileUtils.mkdir_p("test")
        File.write("spec/a_spec.rb", "")
        File.write("test/b_test.rb", "")
        list = File.join(dir, "paths.txt")
        File.write(list, "spec/a_spec.rb\ntest/b_test.rb\n")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, "exit 0\n")

        _out, status = polyrun(
          "run-shards", "--workers", "1", "--paths-file", list, "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
      end
    end
  end
end
