require "spec_helper"
require "fileutils"

RSpec.describe "Polyrun::CLI default run" do
  it "exits 2 with no tests in empty directory" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        out, status = polyrun
        expect(status.exitstatus).to eq(2)
        expect(out).to match(/no tests found/)
      end
    end
  end
end
