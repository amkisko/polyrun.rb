require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Polyrun::Partition::PathsBuild do
  describe ".build_ordered_paths" do
    it "sorts all_glob when stages empty" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "b_spec.rb"), "")
        File.write(File.join(dir, "spec", "a_spec.rb"), "")
        pb = {"all_glob" => "spec/**/*_spec.rb", "stages" => []}
        got = described_class.build_ordered_paths(pb, dir)
        expect(got).to eq(%w[spec/a_spec.rb spec/b_spec.rb])
      end
    end

    it "orders integration files by substring priority then the rest" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "integration"))
        %w[zz_spec.rb audits_spec.rb revisions_spec.rb other_spec.rb].each do |f|
          File.write(File.join(dir, "spec", "integration", f), "")
        end
        File.write(File.join(dir, "spec", "unit_spec.rb"), "")
        pb = {
          "all_glob" => "spec/**/*_spec.rb",
          "stages" => [
            {
              "glob" => "spec/integration/**/*_spec.rb",
              "sort_by_substring_order" => %w[revisions_spec audits_spec],
              "default_priority" => 5
            }
          ]
        }
        got = described_class.build_ordered_paths(pb, dir)
        expect(got).to eq(%w[
          spec/integration/revisions_spec.rb
          spec/integration/audits_spec.rb
          spec/integration/other_spec.rb
          spec/integration/zz_spec.rb
          spec/unit_spec.rb
        ])
      end
    end

    it "takes regex stage first then remainder (Rails paths convention)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "my_federation_controller_spec.rb"), "")
        File.write(File.join(dir, "spec", "plain_spec.rb"), "")
        pb = {
          "all_glob" => "spec/**/*_spec.rb",
          "stages" => [
            {"regex" => "federation_controller|railtie", "ignore_case" => true}
          ]
        }
        got = described_class.build_ordered_paths(pb, dir)
        expect(got).to eq(%w[spec/my_federation_controller_spec.rb spec/plain_spec.rb])
      end
    end

    it "multi-stage glob stages consume the pool once each (no dupes, no drops)" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec", "batch_a"))
        FileUtils.mkdir_p(File.join(dir, "spec", "batch_b"))
        50.times do |i|
          File.write(File.join(dir, "spec", "batch_a", "a_#{i}_spec.rb"), "")
        end
        50.times do |i|
          File.write(File.join(dir, "spec", "batch_b", "b_#{i}_spec.rb"), "")
        end
        pb = {
          "all_glob" => "spec/**/*_spec.rb",
          "stages" => [
            {"glob" => "spec/batch_a/**/*_spec.rb"},
            {"glob" => "spec/batch_b/**/*_spec.rb"}
          ]
        }
        got = described_class.build_ordered_paths(pb, dir)
        expect(got.size).to eq(100)
        expect(got.uniq.size).to eq(100)
        expect(got.take(50).all? { |p| p.start_with?("spec/batch_a/") }).to be true
        expect(got.drop(50).all? { |p| p.start_with?("spec/batch_b/") }).to be true
      end
    end
  end

  describe ".apply!" do
    it "writes paths_file from config" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "x_spec.rb"), "")
        File.write(File.join(dir, "polyrun.yml"), <<~YAML)
          partition:
            paths_file: spec/spec_paths.txt
            paths_build:
              all_glob: spec/**/*_spec.rb
              stages: []
        YAML
        cfg = Polyrun::Config.load(path: File.join(dir, "polyrun.yml"))
        expect(described_class.apply!(partition: cfg.partition, cwd: dir)).to eq(0)
        lines = File.read(File.join(dir, "spec", "spec_paths.txt")).split("\n").reject(&:empty?)
        expect(lines).to eq(%w[spec/x_spec.rb])
      end
    end
  end
end
