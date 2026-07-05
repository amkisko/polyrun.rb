require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Polyrun::CLI do
  describe "run-queue validation" do
    it "exits 2 without -- separator" do
      out, st = polyrun("run-queue", "--workers", "1")
      expect(st.exitstatus).to eq(2)
      expect(out).to include("need --")
    end

    it "exits 2 without paths file" do
      out, st = polyrun("run-queue", "--workers", "1", "--", "true")
      expect(st.exitstatus).to eq(2)
      expect(out).to include("need --paths-file")
    end

    it "exits 2 when queue directory already exists" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          list = File.join(dir, "paths.txt")
          File.write(list, "a.rb\n")
          polyrun("run-queue", "--workers", "1", "--batch", "1", "--dir", ".rq", "--paths-file", list, "--", "true")
          out, st = polyrun("run-queue", "--workers", "1", "--batch", "1", "--dir", ".rq", "--paths-file", list, "--", "true")
          expect(st.exitstatus).to eq(2)
          expect(out).to include("queue already exists")
        end
      end
    end
  end
end
