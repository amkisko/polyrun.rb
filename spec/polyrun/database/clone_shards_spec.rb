require "spec_helper"

RSpec.describe Polyrun::Database::CloneShards do
  let(:dh) do
    {
      "template_db" => "app_tpl",
      "shard_db_pattern" => "myapp_test_%{shard}",
      "postgresql" => {"host" => "localhost", "port" => "5432", "username" => "postgres"},
      "connections" => [
        {"name" => "warehouse", "template_db" => "wh_tpl", "shard_db_pattern" => "wh_test_%{shard}"}
      ]
    }
  end

  it "dry-run prints migrate and create lines without calling psql or rails" do
    expect(Polyrun::Database::Provision).not_to receive(:prepare_template!)
    expect(Polyrun::Database::Provision).not_to receive(:drop_database_if_exists!)
    expect(Polyrun::Database::Provision).not_to receive(:create_database_from_template!)

    described_class.provision!(
      dh,
      workers: 2,
      rails_root: "/tmp",
      migrate: true,
      replace: true,
      dry_run: true,
      silent: true
    )
  end

  it "creates shard databases in parallel after a single db:prepare" do
    allow(Polyrun::Database::Provision).to receive(:prepare_template!).and_return(true)
    allow(Polyrun::Database::Provision).to receive(:drop_database_if_exists!).and_return(true)
    allow(Polyrun::Database::Provision).to receive(:create_database_from_template!).and_return(true)

    described_class.provision!(
      dh,
      workers: 2,
      rails_root: "/tmp",
      migrate: true,
      replace: true,
      dry_run: false,
      silent: true
    )

    expect(Polyrun::Database::Provision).to have_received(:prepare_template!).once
    expect(Polyrun::Database::Provision).to have_received(:create_database_from_template!).exactly(4).times
  end

  it "includes shard_index in parallel provision errors" do
    allow(Polyrun::Database::Provision).to receive(:prepare_template!).and_return(true)
    allow(Polyrun::Database::Provision).to receive(:drop_database_if_exists!).and_return(true)
    allow(Polyrun::Database::Provision).to receive(:create_database_from_template!) do |**kwargs|
      raise Polyrun::Error, "create failed for #{kwargs[:new_db]}" if kwargs[:new_db] == "wh_test_1"

      true
    end

    old_report = Thread.report_on_exception
    Thread.report_on_exception = false
    expect do
      described_class.provision!(
        dh,
        workers: 2,
        rails_root: "/tmp",
        migrate: true,
        replace: true,
        dry_run: false,
        silent: true
      )
    end.to raise_error(Polyrun::Error, /CloneShards shard_index=1: create failed for wh_test_1/)
  ensure
    Thread.report_on_exception = old_report if defined?(old_report)
  end

  it "raises before psql when databases adapter is not PostgreSQL" do
    mysql_dh = {
      "template_db" => "app_tpl",
      "shard_db_pattern" => "myapp_test_%{shard}",
      "mysql2" => {"host" => "127.0.0.1", "port" => "3306", "username" => "app_test"}
    }
    expect(Polyrun::Database::Provision).not_to receive(:prepare_template!)
    expect(Polyrun::Database::Provision).not_to receive(:create_database_from_template!)

    expect do
      described_class.provision!(
        mysql_dh,
        workers: 1,
        rails_root: "/tmp",
        migrate: true,
        replace: true,
        dry_run: false,
        silent: true
      )
    end.to raise_error(Polyrun::Error, /PostgreSQL-only.*mysql2/i)
  end

  it "passes postgresql connection settings from databases hash to Provision" do
    allow(Polyrun::Database::Provision).to receive(:prepare_template!).and_return(true)
    allow(Polyrun::Database::Provision).to receive(:drop_database_if_exists!).and_return(true)
    allow(Polyrun::Database::Provision).to receive(:create_database_from_template!).and_return(true)

    custom = dh.merge(
      "postgresql" => {
        "host" => "db.internal",
        "port" => "5433",
        "username" => "app_user",
        "password" => "secret"
      }
    )
    described_class.provision!(
      custom,
      workers: 1,
      rails_root: "/tmp",
      migrate: false,
      replace: true,
      dry_run: false,
      silent: true
    )

    expect(Polyrun::Database::Provision).to have_received(:create_database_from_template!).with(
      hash_including(
        new_db: "myapp_test_0",
        template_db: "app_tpl",
        host: "db.internal",
        port: "5433",
        username: "app_user",
        password: "secret"
      )
    )
  end
end
