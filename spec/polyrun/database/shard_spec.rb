require "spec_helper"

RSpec.describe Polyrun::Database::Shard do
  it "expands database name template" do
    expect(described_class.expand_database_name("app_test_%{shard}", 3)).to eq("app_test_3")
  end

  it "builds env map" do
    m = described_class.env_map(shard_index: 1, shard_total: 4, base_database: "db_%{shard}")
    expect(m["POLYRUN_SHARD_INDEX"]).to eq("1")
    expect(m["POLYRUN_TEST_DATABASE"]).to eq("db_1")
  end

  it "suffixes database in postgres URL" do
    u = "postgres://u:p@host:5432/myapp_test"
    expect(described_class.database_url_with_shard(u, 2)).to include("myapp_test_2")
  end

  it "suffixes database in mysql2 URL" do
    u = "mysql2://root@127.0.0.1:3306/myapp_test"
    expect(described_class.database_url_with_shard(u, 1)).to include("myapp_test_1")
  end

  it "suffixes database name in mongodb URL" do
    u = "mongodb://127.0.0.1:27017/myapp_test"
    expect(described_class.database_url_with_shard(u, 3)).to include("myapp_test_3")
  end

  it "suffixes basename in sqlite3 URL" do
    u = "sqlite3:db/myapp_test.sqlite3"
    expect(described_class.database_url_with_shard(u, 2)).to eq("sqlite3:db/myapp_test_2.sqlite3")
  end
end
