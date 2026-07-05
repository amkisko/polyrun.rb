require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Polyrun::CLI do
  describe "run-queue" do
    it "runs batches and exits 0 when all pass" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          list = File.join(dir, "paths.txt")
          File.write(list, "ok.rb\n")
          out, st = polyrun(
            "run-queue", "--workers", "1", "--batch", "1",
            "--dir", ".rq", "--paths-file", list,
            "--", "ruby", "-e", "exit 0"
          )
          expect(st.exitstatus).to eq(0)
          expect(out).to include("done pending=0")
        end
      end
    end

    it "exits 1 and reclaims leased paths when a batch fails" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          list = File.join(dir, "paths.txt")
          File.write(list, "aaa_ok.rb\nzzz_fail.rb\n")
          script = 'exit(ARGV.any? { |p| File.basename(p).include?("fail") } ? 1 : 0)'
          out, st = polyrun(
            "run-queue", "--workers", "1", "--batch", "1",
            "--dir", ".rq", "--paths-file", list,
            "--", "ruby", "-e", script
          )
          expect(st.exitstatus).to eq(1)
          expect(out).to include("reclaimed 1 path")
          store = Polyrun::Queue::FileStore.new(".rq")
          stat = store.status
          expect(stat["done"]).to eq(1)
          expect(stat["pending"]).to eq(1)
        end
      end
    end

    it "runs with multiple workers" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          list = File.join(dir, "paths.txt")
          File.write(list, "a.rb\nb.rb\nc.rb\n")
          out, st = polyrun(
            "run-queue", "--workers", "2", "--batch", "1",
            "--dir", ".rq2", "--paths-file", list,
            "--", "ruby", "-e", "exit 0"
          )
          expect(st.exitstatus).to eq(0)
          expect(out).to include("done pending=0")
        end
      end
    end

    it "requeues leased paths when --on-failure requeue and a batch fails" do
      Dir.mktmpdir do |dir|
        with_chdir(dir) do
          list = File.join(dir, "paths.txt")
          File.write(list, "fail.rb\n")
          out, st = polyrun(
            "run-queue", "--workers", "1", "--batch", "1", "--on-failure", "requeue",
            "--dir", ".rq3", "--paths-file", list,
            "--", "ruby", "-e", "exit 1"
          )
          expect(st.exitstatus).to eq(1)
          store = Polyrun::Queue::FileStore.new(".rq3")
          expect(store.status["pending"]).to eq(1)
          expect(store.status["leases"]).to eq(0)
        end
      end
    end
  end
end
