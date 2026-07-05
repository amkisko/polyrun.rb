require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe Polyrun::Data::SqlSnapshot do
  describe ".create!" do
    it "raises when database is not configured" do
      ENV.delete("PGDATABASE")
      root = Dir.mktmpdir
      expect do
        described_class.create!("base", root: root)
      end.to raise_error(Polyrun::Error, /database/)
    end

    it "writes pg_dump stdout to spec/fixtures/sql_snapshots/<name>.sql" do
      root = Dir.mktmpdir
      allow(Open3).to receive(:capture3).and_return(["SELECT 1;\n", "", instance_double(Process::Status, success?: true)])
      path = described_class.create!("base", root: root, database: "mydb", username: "u")
      expected = File.join(root, "spec", "fixtures", "sql_snapshots", "base.sql")
      expect(path).to eq(expected)
      expect(File.read(path)).to eq("SELECT 1;\n")
    end

    it "raises when pg_dump fails" do
      root = Dir.mktmpdir
      allow(Open3).to receive(:capture3).and_return(["", "boom", instance_double(Process::Status, success?: false)])
      expect do
        described_class.create!("base", root: root, database: "mydb", username: "u")
      end.to raise_error(Polyrun::Error, /pg_dump failed/)
    end

    it "includes host and port in pg_dump command" do
      root = Dir.mktmpdir
      allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])
      described_class.create!("base", root: root, database: "mydb", username: "u", host: "db.local", port: 5433)
      expect(Open3).to have_received(:capture3).with("pg_dump", "--data-only", "-U", "u", "-h", "db.local", "-p", "5433", "mydb")
    end
  end

  describe ".default_connection" do
    it "reads database and username from ENV" do
      ENV["PGDATABASE"] = "from_env"
      ENV["PGUSER"] = "env_user"
      expect(described_class.default_connection[:database]).to eq("from_env")
      expect(described_class.default_connection[:username]).to eq("env_user")
    end
  end

  describe ".load!" do
    it "raises when snapshot file is missing" do
      expect do
        described_class.load!("missing", root: Dir.mktmpdir, database: "d", username: "u")
      end.to raise_error(Polyrun::Error, /missing/)
    end

    it "truncates tables and loads snapshot SQL" do
      root = Dir.mktmpdir
      path = File.join(root, "spec", "fixtures", "sql_snapshots", "base.sql")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "SELECT 1;\n")
      allow(Open3).to receive(:capture3).and_return(
        ["", "", instance_double(Process::Status, success?: true)],
        ["", "", instance_double(Process::Status, success?: true)]
      )
      expect(described_class.load!("base", root: root, database: "d", username: "u", tables: %w[users])).to be true
    end

    it "raises when psql truncate fails" do
      root = Dir.mktmpdir
      path = File.join(root, "spec", "fixtures", "sql_snapshots", "base.sql")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "SELECT 1;\n")
      allow(Open3).to receive(:capture3).and_return(["", "trunc err", instance_double(Process::Status, success?: false)])
      expect do
        described_class.load!("base", root: root, database: "d", username: "u", tables: %w[users])
      end.to raise_error(Polyrun::Error, /truncate failed/)
    end

    it "raises when psql load fails" do
      root = Dir.mktmpdir
      path = File.join(root, "spec", "fixtures", "sql_snapshots", "base.sql")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "BAD;\n")
      allow(Open3).to receive(:capture3).and_return(["", "err", instance_double(Process::Status, success?: false)])
      expect do
        described_class.load!("base", root: root, database: "d", username: "u", tables: [])
      end.to raise_error(Polyrun::Error, /psql load failed/)
    end
  end
end
