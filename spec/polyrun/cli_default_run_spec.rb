require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe "Polyrun::CLI default run" do
  it "exits 2 with no tests in empty directory" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        out, status = polyrun
        expect(status.exitstatus).to eq(2)
        expect(out).to include("no tests found")
      end
    end
  end

  it "exits 2 when implicit path arguments match no files" do
    out, status = polyrun("spec/missing_*_spec.rb")
    expect(status.exitstatus).to eq(2)
    expect(out).to include("no files matched")
  end

  it "exits 2 when mixing spec and test paths" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        FileUtils.mkdir_p("test")
        File.write("spec/a_spec.rb", "")
        File.write("test/b_test.rb", "")
        out, status = polyrun("spec/a_spec.rb", "test/b_test.rb")
        expect(status.exitstatus).to eq(2)
        expect(out).to include("mixing")
      end
    end
  end

  it "keeps --paths-file before -- and leaves the worker command intact" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        FileUtils.mkdir_p("spec")
        File.write("spec/a_spec.rb", "")
        File.write("spec/b_spec.rb", "")
        File.write("polyrun.yml", <<~YAML)
          partition:
            shard_total: 1
            paths_file: spec/paths.txt
        YAML
        File.write("spec/paths.txt", "spec/b_spec.rb\n")
        stub = File.join(dir, "_shard.rb")
        File.write(stub, <<~RUBY)
          File.write("argv.txt", ARGV.join("\\n"))
          exit 0
        RUBY
        out, status = polyrun(
          "-c", "polyrun.yml", "spec/a_spec.rb", "--workers", "1", "--", RbConfig.ruby, stub
        )
        expect(status.success?).to eq(true), out
        argv = File.read(File.join(dir, "argv.txt"))
        expect(argv).not_to include("--paths-file")
        # Worker ARGV is the shard paths; implicit a_spec must win over polyrun.yml paths_file (b_spec).
        expect(argv).to include("a_spec.rb")
        expect(argv).not_to include("b_spec.rb")
      end
    end
  end
end
