require "spec_helper"
require "tmpdir"

RSpec.describe Polyrun::Data::Fixtures do
  it "loads yaml and iterates tables" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "users.yml")
      File.write(path, <<~YAML)
        users:
          - name: Ada
            email: ada@example.com
        _meta:
          note: ignored
      YAML
      batch = described_class.load_yaml(path)
      rows = []
      described_class.each_table(batch) { |t, r| rows << [t, r] }
      expect(rows.size).to eq(1)
      expect(rows[0][0]).to eq("users")
      expect(rows[0][1].first["name"]).to eq("Ada")
    end
  end

  it "loads directory of batches" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a.yml"), "t:\n  - id: 1\n")
      all = described_class.load_directory(dir)
      expect(all.keys).to include("a")
    end
  end

  it "apply_insert_all! delegates to ActiveRecord connection" do
    conn = double("connection", insert_all: nil)
    fake_ar = Class.new do
      define_singleton_method(:connection) { conn }
    end
    stub_const("ActiveRecord::Base", fake_ar)
    batch = {"users" => [{"name" => "Ada"}]}
    described_class.apply_insert_all!(batch)
    expect(conn).to have_received(:insert_all).with("users", [{"name" => "Ada"}])
  end
end
