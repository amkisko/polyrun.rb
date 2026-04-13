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
  end

  describe ".load!" do
    it "raises when snapshot file is missing" do
      expect do
        described_class.load!("missing", root: Dir.mktmpdir, database: "d", username: "u")
      end.to raise_error(Polyrun::Error, /missing/)
    end
  end
end
