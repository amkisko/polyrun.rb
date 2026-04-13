require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Polyrun::Coverage::TrackFiles do
  describe ".expand_globs" do
    it "expands brace alternation relative to root" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "a"))
        File.write(File.join(root, "lib", "a", "x.rb"), "x\n")
        FileUtils.mkdir_p(File.join(root, "app"))
        File.write(File.join(root, "app", "y.rb"), "y\n")
        paths = described_class.expand_globs(root, "{lib,app}/**/*.rb")
        expect(paths.size).to eq(2)
        expect(paths).to include(File.join(root, "lib", "a", "x.rb"))
        expect(paths).to include(File.join(root, "app", "y.rb"))
      end
    end
  end

  describe ".merge_untracked_into_blob" do
    it "adds simulated coverage for files not in the blob" do
      Dir.mktmpdir do |root|
        f = File.join(root, "lib", "orphan.rb")
        FileUtils.mkdir_p(File.dirname(f))
        File.write(f, "# c\n\nclass X; end\n")
        blob = {}
        out = described_class.merge_untracked_into_blob(blob, root, "lib/**/*.rb")
        expect(out).to have_key(f)
        expect(out[f]["lines"][0]).to be_nil # comment
        expect(out[f]["lines"].last).to eq(0)
      end
    end
  end

  describe ".group_summaries" do
    it "builds SimpleCov-compatible group stats and Ungrouped" do
      root = "/project"
      blob = {
        "/project/lib/a.rb" => {"lines" => [nil, 1]},
        "/project/lib/b.rb" => {"lines" => [nil, 0]},
        "/project/other/z.rb" => {"lines" => [1]},
        "/project/unmatched.rb" => {"lines" => [1]}
      }
      groups = {
        "Lib" => "lib/**/*.rb",
        "Other" => "other/**/*.rb"
      }
      g = described_class.group_summaries(blob, root, groups)
      expect(g["Lib"]).to include("lines")
      expect(g["Lib"]["lines"]["covered_percent"]).to be_a(Float)
      expect(g["Other"]["lines"]["covered_percent"]).to eq(100.0)
      expect(g["Ungrouped"]["lines"]["covered_percent"]).to eq(100.0)
    end
  end
end
