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
end
