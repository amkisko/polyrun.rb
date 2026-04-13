require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

# Contracts for parallel CI / multi-process test runners: assets markers, fixtures idempotence,
# shard isolation, and pure merge (no hidden globals). See examples/TESTING_REQUIREMENTS.md.
RSpec.describe "Mandatory parallel testing support" do
  describe "Prepare::Assets (shared builds)" do
    it "uses a digest marker so unchanged sources skip redundant work" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "app", "assets")
        FileUtils.mkdir_p(src)
        f = File.join(src, "a.css")
        File.write(f, "x{}")

        marker = File.join(dir, "tmp", "digest.txt")
        Polyrun::Prepare::Assets.write_marker!(marker, src)
        expect(Polyrun::Prepare::Assets.stale?(marker, src)).to be false

        File.write(f, "y{}")
        expect(Polyrun::Prepare::Assets.stale?(marker, src)).to be true
      end
    end
  end

  describe "Data::Fixtures (shared YAML)" do
    it "load_directory is deterministic when called twice" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "batch.yml"), "users:\n  - id: 1\n")
        a = Polyrun::Data::Fixtures.load_directory(dir)
        b = Polyrun::Data::Fixtures.load_directory(dir)
        expect(a).to eq(b)
      end
    end
  end

  describe "Database::Shard (no cross-worker DB contention)" do
    it "produces distinct database names per shard index" do
      a = Polyrun::Database::Shard.env_map(shard_index: 0, shard_total: 4, base_database: "app_test_%{shard}")
      b = Polyrun::Database::Shard.env_map(shard_index: 1, shard_total: 4, base_database: "app_test_%{shard}")
      expect(a["POLYRUN_TEST_DATABASE"]).not_to eq(b["POLYRUN_TEST_DATABASE"])
    end
  end

  describe "Coverage::Merge (GVL-friendly: pure functions)" do
    it "concurrent merges of disjoint blobs match sequential merge" do
      a = {"/1.rb" => {"lines" => [1]}}
      b = {"/2.rb" => {"lines" => [2]}}
      c = {"/3.rb" => {"lines" => [3]}}
      left = Polyrun::Coverage::Merge.merge_two(Polyrun::Coverage::Merge.merge_two(a, b), c)
      threads = [
        Thread.new { Polyrun::Coverage::Merge.merge_two(a, b) },
        Thread.new { c.dup }
      ]
      m1 = threads[0].value
      m2 = threads[1].value
      combined = Polyrun::Coverage::Merge.merge_two(m1, m2)
      expect(combined).to eq(left)
    end
  end

  describe "Data::FactoryCounts" do
    it "documents reset between serial suites (use process isolation for parallel runners)" do
      Polyrun::Data::FactoryCounts.reset!
      Polyrun::Data::FactoryCounts.record(:widget)
      expect(Polyrun::Data::FactoryCounts.counts["widget"]).to eq(1)
      Polyrun::Data::FactoryCounts.reset!
      expect(Polyrun::Data::FactoryCounts.counts).to be_empty
    end
  end

  describe "Data::CachedFixtures (process-local memoization)" do
    it "returns the same object for repeated fetch in one process" do
      Polyrun::Data::CachedFixtures.reset!
      Polyrun::Data::CachedFixtures.enable!
      a = Polyrun::Data::CachedFixtures.fetch(:k) { Object.new }
      b = Polyrun::Data::CachedFixtures.fetch(:k) { Object.new }
      expect(a.object_id).to eq(b.object_id)
    end
  end

  describe "Data::ParallelProvisioning (shard-aware hooks)" do
    around do |example|
      saved = %w[POLYRUN_SHARD_TOTAL].to_h { |k| [k, ENV[k]] }
      example.run
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "invokes parallel_worker when POLYRUN_SHARD_TOTAL > 1" do
      Polyrun::Data::ParallelProvisioning.reset_configuration!
      log = []
      Polyrun::Data::ParallelProvisioning.configure do |c|
        c.serial { log << :s }
        c.parallel_worker { log << :p }
      end
      ENV["POLYRUN_SHARD_TOTAL"] = "2"
      Polyrun::Data::ParallelProvisioning.run_suite_hooks!
      expect(log).to eq([:p])
    end
  end
end
