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

  it "template_prepare_env sets DATABASE_URL and per-connection keys for a single db:prepare" do
    dh_multi = dh.merge(
      "connections" => [
        {"name" => "warehouse", "shard_db_pattern" => "wh_test_%{shard}", "template_db" => "wh_tpl", "env_key" => "WH_DATABASE_URL"}
      ]
    )
    te = described_class.template_prepare_env(dh_multi)
    expect(te["DATABASE_URL"]).to end_with("/app_tpl")
    expect(te["WH_DATABASE_URL"]).to end_with("/wh_tpl")
  end

  it "template_prepare_env raises without template_db" do
    expect { described_class.template_prepare_env({}) }.to raise_error(Polyrun::Error, /template_db/)
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

  it "builds mysql2 URLs when mysql block is present" do
    dh_mysql = {
      "template_db" => "tpl",
      "shard_db_pattern" => "app_test_%{shard}",
      "mysql" => {"host" => "127.0.0.1", "port" => "3306", "username" => "root"}
    }
    u = described_class.url_for_shard(dh_mysql, shard_index: 1)
    expect(u).to start_with("mysql2://root@127.0.0.1:3306/")
    expect(u).to end_with("/app_test_1")
  end

  it "builds mongodb URLs when mongo block is present" do
    dh_m = {
      "template_db" => "tpl",
      "shard_db_pattern" => "app_test_%{shard}",
      "mongo" => {"host" => "127.0.0.1", "port" => "27017"}
    }
    u = described_class.url_for_shard(dh_m, shard_index: 0)
    expect(u).to eq("mongodb://127.0.0.1:27017/app_test_0")
  end

  it "respects explicit adapter with top-level host" do
    dh_flat = {
      "adapter" => "mysql2",
      "host" => "db.internal",
      "mysql2" => {"username" => "u", "password" => "p"}
    }
    u = described_class.url_for_database_name(dh_flat, "mydb")
    expect(u).to eq("mysql2://u:p@db.internal:3306/mydb")
  end

  it "builds sqlserver URLs" do
    dh = {
      "shard_db_pattern" => "app_%{shard}",
      "sqlserver" => {"host" => "db", "port" => "1433", "username" => "sa", "password" => "x"}
    }
    u = described_class.url_for_shard(dh, shard_index: 1)
    expect(u).to eq("sqlserver://sa:x@db:1433/app_1")
  end

  it "builds trilogy URLs" do
    dh = {
      "shard_db_pattern" => "t_%{shard}",
      "trilogy" => {"host" => "127.0.0.1", "username" => "root"}
    }
    u = described_class.url_for_shard(dh, shard_index: 0)
    expect(u).to start_with("trilogy://root@127.0.0.1:3306/")
    expect(u).to end_with("/t_0")
  end

  it "builds sqlite3 URLs and extract_db_name" do
    dh = {
      "shard_db_pattern" => "db/app_test_%{shard}.sqlite3",
      "sqlite3" => {}
    }
    u = described_class.url_for_shard(dh, shard_index: 2)
    expect(u).to eq("sqlite3:db/app_test_2.sqlite3")
    expect(described_class.extract_db_name(u)).to eq("db/app_test_2.sqlite3")
  end
end
