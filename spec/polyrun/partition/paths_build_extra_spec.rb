require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Polyrun::Partition::PathsBuild do
  describe ".skip_paths_build?" do
    it "returns true when POLYRUN_SKIP_PATHS_BUILD is set" do
      old = ENV["POLYRUN_SKIP_PATHS_BUILD"]
      ENV["POLYRUN_SKIP_PATHS_BUILD"] = "1"
      expect(described_class.skip_paths_build?).to be true
      ENV["POLYRUN_SKIP_PATHS_BUILD"] = old
    end
  end

  describe ".apply!" do
    it "returns 0 when skip env is set" do
      old = ENV["POLYRUN_SKIP_PATHS_BUILD"]
      ENV["POLYRUN_SKIP_PATHS_BUILD"] = "1"
      expect(described_class.apply!(partition: {"paths_build" => {"all_glob" => "spec/**/*_spec.rb"}}, cwd: Dir.pwd)).to eq(0)
      ENV["POLYRUN_SKIP_PATHS_BUILD"] = old
    end

    it "returns 0 when paths_build is absent" do
      old = ENV.delete("POLYRUN_SKIP_PATHS_BUILD")
      begin
        expect(described_class.apply!(partition: {"paths_file" => "spec/spec_paths.txt"}, cwd: Dir.pwd)).to eq(0)
      ensure
        ENV["POLYRUN_SKIP_PATHS_BUILD"] = "1" if old.nil?
      end
    end

    it "returns 2 when a stage is invalid" do
      old = ENV.delete("POLYRUN_SKIP_PATHS_BUILD")
      begin
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "spec"))
          File.write(File.join(dir, "spec", "a_spec.rb"), "")
          pb = {"all_glob" => "spec/**/*_spec.rb", "stages" => [{"sort_by_substring_order" => []}]}
          expect(described_class.apply!(partition: {"paths_build" => pb, "paths_file" => "spec/spec_paths.txt"}, cwd: dir)).to eq(2)
        end
      ensure
        ENV["POLYRUN_SKIP_PATHS_BUILD"] = "1" if old.nil?
      end
    end
  end

  describe ".build_ordered_paths regex stage" do
    it "matches basename with ignore_case" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "My_Railtie_spec.rb"), "")
        File.write(File.join(dir, "spec", "plain_spec.rb"), "")
        pb = {
          "all_glob" => "spec/**/*_spec.rb",
          "stages" => [{"regex" => "railtie", "ignore_case" => true}]
        }
        got = described_class.build_ordered_paths(pb, dir)
        expect(got.first).to eq("spec/My_Railtie_spec.rb")
      end
    end
  end
end
