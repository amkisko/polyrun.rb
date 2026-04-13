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
end
