require "spec_helper"
require "fileutils"
require "rbconfig"

RSpec.describe Polyrun::Partition::Suite do
  describe ".resolve_default" do
    it "prefers paths_file inference over filesystem auto-detect when both trees exist" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "spec", "a_spec.rb"), "")
        test = File.join(dir, "test", "b_test.rb")
        File.write(test, "")
        list = File.join(dir, "paths.txt")
        File.write(list, "#{test}\n")

        r = described_class.resolve_default(
          cwd: dir,
          partition: {"paths_file" => "paths.txt", "suite" => "auto"}
        )
        expect(r[:suite]).to eq(:minitest)
        expect(r[:error]).to be_nil
      end
    end

    it "honors explicit partition.suite over filesystem auto-detect" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        FileUtils.mkdir_p(File.join(dir, "test"))
        File.write(File.join(dir, "spec", "a_spec.rb"), "")
        File.write(File.join(dir, "test", "b_test.rb"), "")

        r = described_class.resolve_default(cwd: dir, partition: {"suite" => "minitest"})
        expect(r[:suite]).to eq(:minitest)
      end
    end

    it "fails when partition.suite disagrees with paths_file inference" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "test"))
        test = File.join(dir, "test", "b_test.rb")
        File.write(test, "")
        list = File.join(dir, "paths.txt")
        File.write(list, "#{test}\n")

        r = described_class.resolve_default(
          cwd: dir,
          partition: {"paths_file" => "paths.txt", "suite" => "rspec"}
        )
        expect(r[:suite]).to be_nil
        expect(r[:error]).to include("partition.suite")
        expect(r[:error]).to include("minitest")
      end
    end

    it "falls back to detect_auto_suite when suite is auto and no paths_file" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "spec"))
        File.write(File.join(dir, "spec", "a_spec.rb"), "")

        r = described_class.resolve_default(cwd: dir, partition: {})
        expect(r[:suite]).to eq(:rspec)
      end
    end
  end

  describe ".infer_from_command" do
    it "detects rspec, minitest, and quick commands" do
      expect(described_class.infer_from_command(%w[bundle exec rspec])).to eq(:rspec)
      expect(described_class.infer_from_command(%w[bundle exec rails test])).to eq(:minitest)
      expect(described_class.infer_from_command(%w[bundle exec ruby -I test])).to eq(:minitest)
      expect(described_class.infer_from_command(%w[bundle exec polyrun quick])).to eq(:quick)
      expect(described_class.infer_from_command([RbConfig.ruby, "stub.rb"])).to be_nil
    end

    it "detects bin/rails test and compact ruby -Itest" do
      expect(described_class.infer_from_command(%w[bin/rails test])).to eq(:minitest)
      expect(described_class.infer_from_command(%w[bundle exec ruby -Itest])).to eq(:minitest)
    end
  end

  describe ".command_mismatch_message" do
    it "reports when path list and command suites disagree" do
      msg = described_class.command_mismatch_message(
        ["test/a_test.rb"],
        %w[bundle exec rspec]
      )
      expect(msg).to include("minitest")
      expect(msg).to include("rspec")
    end

    it "returns nil for custom commands" do
      expect(
        described_class.command_mismatch_message(["test/a_test.rb"], [RbConfig.ruby, "stub.rb"])
      ).to be_nil
    end

    it "rejects mixed lists only when the command is a known single-suite runner" do
      mixed = %w[spec/a_spec.rb test/b_test.rb]
      expect(described_class.command_mismatch_message(mixed, %w[bundle exec rspec])).to include("mixing")
      expect(described_class.command_mismatch_message(mixed, [RbConfig.ruby, "stub.rb"])).to be_nil
    end

    it "treats path:line RSpec locators as rspec" do
      expect(
        described_class.command_mismatch_message(["spec/a_spec.rb:1"], %w[bundle exec rspec])
      ).to be_nil
    end
  end
end
