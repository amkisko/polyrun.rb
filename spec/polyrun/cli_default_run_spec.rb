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
end
