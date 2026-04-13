require "spec_helper"

RSpec.describe Polyrun::Database::UrlBuilder do
  let(:dh) do
    {
      "template_db" => "app_tpl",
      "shard_db_pattern" => "myapp_test_%{shard}",
      "postgresql" => {"host" => "localhost", "port" => "5432", "username" => "postgres"}
    }
  end

  it "builds template URL" do
    u = described_class.postgres_url_for_template(dh)
    expect(u).to include("postgres://postgres@localhost:5432/app_tpl")
  end

  it "builds shard URL and env exports" do
    u = described_class.postgres_url_for_shard(dh, shard_index: 2)
    expect(u).to end_with("/myapp_test_2")
    ex = described_class.env_exports_for_databases(dh, shard_index: 2)
    expect(ex["DATABASE_URL"]).to eq(u)
    expect(ex["TEST_DB_NAME"]).to eq("myapp_test_2")
  end

  it "exports DATABASE_URL_<NAME> for named connections with their own patterns" do
    dh_multi = dh.merge(
      "connections" => [
        {"name" => "warehouse", "shard_db_pattern" => "wh_test_%{shard}"}
      ]
    )
    ex = described_class.env_exports_for_databases(dh_multi, shard_index: 1)
    expect(ex["DATABASE_URL"]).to end_with("/myapp_test_1")
    expect(ex["DATABASE_URL_WAREHOUSE"]).to end_with("/wh_test_1")
  end

  it "exports named connections with custom env_key when set" do
    dh_multi = dh.merge(
      "connections" => [
        {"name" => "cache", "shard_db_pattern" => "cache_test_%{shard}", "env_key" => "CACHE_DATABASE_URL"}
      ]
    )
    ex = described_class.env_exports_for_databases(dh_multi, shard_index: 0)
    expect(ex["CACHE_DATABASE_URL"]).to end_with("/cache_test_0")
    expect(ex).not_to have_key("DATABASE_URL_CACHE")
  end

  it "unique_template_migrate_urls includes primary and distinct connection templates" do
    dh_multi = dh.merge(
      "connections" => [
        {"name" => "warehouse", "shard_db_pattern" => "wh_test_%{shard}", "template_db" => "wh_tpl"}
      ]
    )
    urls = described_class.unique_template_migrate_urls(dh_multi)
    expect(urls.size).to eq(2)
    expect(urls[0]).to end_with("/app_tpl")
    expect(urls[1]).to end_with("/wh_tpl")
  end

  it "shard_database_plan lists primary and connection create-from-template rows" do
    dh_multi = dh.merge(
      "connections" => [
        {"name" => "warehouse", "shard_db_pattern" => "wh_test_%{shard}", "template_db" => "wh_tpl"}
      ]
    )
    plan = described_class.shard_database_plan(dh_multi, shard_index: 2)
    expect(plan).to eq(
      [
        {new_db: "myapp_test_2", template_db: "app_tpl"},
        {new_db: "wh_test_2", template_db: "wh_tpl"}
      ]
    )
  end

  it "template_database_name_for falls back to primary template for a connection" do
    dh_multi = dh.merge(
      "connections" => [
        {"name" => "cache", "shard_db_pattern" => "cache_test_%{shard}"}
      ]
    )
    expect(described_class.template_database_name_for(dh_multi, connection: "cache")).to eq("app_tpl")
  end
end
