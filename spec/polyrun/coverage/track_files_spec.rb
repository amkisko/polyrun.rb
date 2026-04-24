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

  describe ".keep_tracked_files" do
    it "keeps only loaded files matched by track_files" do
      Dir.mktmpdir do |root|
        app_file = File.join(root, "app", "a.rb")
        lib_file = File.join(root, "lib", "b.rb")
        other_file = File.join(root, "spec", "c.rb")
        FileUtils.mkdir_p(File.dirname(app_file))
        FileUtils.mkdir_p(File.dirname(lib_file))
        FileUtils.mkdir_p(File.dirname(other_file))
        File.write(app_file, "x = 1\n")
        File.write(lib_file, "y = 2\n")
        File.write(other_file, "z = 3\n")

        blob = {
          app_file => {"lines" => [1]},
          lib_file => {"lines" => [2]},
          other_file => {"lines" => [3]}
        }

        out = described_class.keep_tracked_files(blob, root, "{app,lib}/**/*.rb")
        expect(out.keys.sort).to eq([app_file, lib_file].sort)
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
