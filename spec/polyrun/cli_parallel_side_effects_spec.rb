require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe "Polyrun::CLI parallel-* side effects" do
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

  it "parallel-minitest does not run prepare bootstrap" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: touch ran_prepare
          partition:
            paths_file: test/paths.txt
        YAML
        FileUtils.mkdir_p("test")
        File.write("test/b_test.rb", "")
        File.write("test/paths.txt", "test/b_test.rb\n")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, "exit 0\n")

        _out, status = polyrun(
          "parallel-minitest", "--workers", "1", "-c", "polyrun.yml", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "ran_prepare"))).to be false
      end
    end
  end

  it "parallel-quick does not run prepare bootstrap" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: touch ran_prepare
          partition:
            suite: quick
        YAML
        FileUtils.mkdir_p("spec/polyrun_quick")
        File.write("spec/polyrun_quick/a.rb", "describe('x') { it('y') {} }\n")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, "exit 0\n")

        _out, status = polyrun(
          "parallel-quick", "--workers", "1", "-c", "polyrun.yml", "--",
          RbConfig.ruby, stub
        )
        expect(status.success?).to be true
        expect(File.file?(File.join(dir, "ran_prepare"))).to be false
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
