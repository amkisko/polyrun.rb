require "spec_helper"
require "fileutils"
require "open3"

RSpec.describe Polyrun::Database::Provision do
  let(:ok_status) { instance_double(Process::Status, success?: true) }
  let(:bad_status) { instance_double(Process::Status, success?: false) }

  describe ".drop_database_if_exists!" do
    it "runs psql and returns true on success" do
      allow(Open3).to receive(:capture3).and_return(["out", "", ok_status])
      expect(described_class.drop_database_if_exists!(database: "dbx")).to be true
      expect(Open3).to have_received(:capture3).once
    end

    it "uses FORCE when force: true" do
      allow(Open3).to receive(:capture3).and_return(["", "", ok_status])
      described_class.drop_database_if_exists!(database: "dbx", force: true)
      expect(Open3).to have_received(:capture3) do |*args|
        expect(args.join(" ")).to include("WITH (FORCE)")
      end
    end

    it "raises Polyrun::Error when psql fails" do
      allow(Open3).to receive(:capture3).and_return(["", "boom", bad_status])
      expect { described_class.drop_database_if_exists!(database: "dbx") }.to raise_error(Polyrun::Error, /drop database failed/)
    end
  end

  describe ".create_database_from_template!" do
    it "runs psql and returns true on success" do
      allow(Open3).to receive(:capture3).and_return(["", "", ok_status])
      expect(described_class.create_database_from_template!(new_db: "n", template_db: "t")).to be true
    end

    it "raises when create fails" do
      allow(Open3).to receive(:capture3).and_return(["", "nope", bad_status])
      expect { described_class.create_database_from_template!(new_db: "n", template_db: "t") }.to raise_error(Polyrun::Error, /create database failed/)
    end
  end

  describe ".prepare_template!" do
    it "raises when bin/rails is missing" do
      Dir.mktmpdir do |dir|
        expect { described_class.prepare_template!(rails_root: dir, env: {"DATABASE_URL" => "x"}) }.to raise_error(Polyrun::Error, /missing/)
      end
    end

    it "raises on failed db:prepare with stderr and stdout in message" do
      Dir.mktmpdir do |dir|
        exe = File.join(dir, "bin", "rails")
        FileUtils.mkdir_p(File.dirname(exe))
        File.write(exe, "#!/bin/sh\nexit 1\n")
        File.chmod(0o755, exe)
        allow(Open3).to receive(:capture3).and_return(["out line", "err line", bad_status])
        expect { described_class.prepare_template!(rails_root: dir, env: {"DATABASE_URL" => "x"}, silent: true) }.to raise_error(Polyrun::Error) do |e|
          expect(e.message).to include("db:prepare failed")
          expect(e.message).to include("stderr")
          expect(e.message).to include("err line")
          expect(e.message).to include("stdout")
          expect(e.message).to include("out line")
        end
      end
    end

    it "returns true on success" do
      Dir.mktmpdir do |dir|
        exe = File.join(dir, "bin", "rails")
        FileUtils.mkdir_p(File.dirname(exe))
        File.write(exe, "#!/bin/sh\nexit 0\n")
        File.chmod(0o755, exe)
        allow(Open3).to receive(:capture3).and_return(["", "", ok_status])
        expect(described_class.prepare_template!(rails_root: dir, env: {"DATABASE_URL" => "x"})).to be true
      end
    end

    it "warns stderr when not silent and stderr present" do
      Dir.mktmpdir do |dir|
        exe = File.join(dir, "bin", "rails")
        FileUtils.mkdir_p(File.dirname(exe))
        File.write(exe, "#!/bin/sh\nexit 0\n")
        File.chmod(0o755, exe)
        allow(Open3).to receive(:capture3).and_return(["", "warn", ok_status])
        err = StringIO.new
        begin
          Polyrun::Log.stderr = err
          described_class.prepare_template!(rails_root: dir, env: {"DATABASE_URL" => "x"}, silent: false)
        ensure
          Polyrun::Log.reset_io!
        end
        expect(err.string).to include("warn")
      end
    end
  end
end
