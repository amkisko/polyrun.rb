require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "db:setup-shard dry-run does not call psql" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          template_db: app_template
          shard_db_pattern: "app_test_%{shard}"
      YAML
      out, status = polyrun("-c", cfg, "db:setup-shard", "--dry-run")
      expect(status.success?).to be true
      expect(out).to include("CREATE DATABASE")
    end
  end

  it "db:clone-shards dry-run lists migrate and drop/create for all shards" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          template_db: app_template
          shard_db_pattern: "app_test_%{shard}"
          connections:
            - name: warehouse
              template_db: wh_template
              shard_db_pattern: "wh_test_%{shard}"
      YAML
      out, status = polyrun("-c", cfg, "db:clone-shards", "--workers", "2", "--dry-run")
      expect(status.success?).to be true
      expect(out.scan("db:migrate").size).to eq(2)
      expect(out).to include("DROP DATABASE IF EXISTS app_test_0")
      expect(out).to include("CREATE DATABASE app_test_0 TEMPLATE app_template")
      expect(out).to include("wh_test_1")
    end
  end

  it "db:setup-shard dry-run lists primary and connection databases" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          template_db: app_template
          shard_db_pattern: "app_test_%{shard}"
          connections:
            - name: warehouse
              template_db: wh_template
              shard_db_pattern: "wh_test_%{shard}"
      YAML
      out, status = polyrun("-c", cfg, "db:setup-shard", "--dry-run")
      expect(status.success?).to be true
      expect(out).to include("CREATE DATABASE app_test_0 TEMPLATE app_template")
      expect(out).to include("CREATE DATABASE wh_test_0 TEMPLATE wh_template")
    end
  end

  it "db:setup-template dry-run prints migrate command when databases configured" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          template_db: app_template
          postgresql:
            host: localhost
            username: postgres
      YAML
      out, status = polyrun("-c", cfg, "db:setup-template", "--dry-run")
      expect(status.success?).to be true
      expect(out).to include("db:migrate")
      expect(out).to include("DATABASE_URL=")
    end
  end

  it "db:setup-template dry-run prints migrate for each distinct connection template" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          template_db: app_template
          postgresql:
            host: localhost
            username: postgres
          connections:
            - name: analytics
              template_db: analytics_template
              shard_db_pattern: "analytics_test_%{shard}"
      YAML
      out, status = polyrun("-c", cfg, "db:setup-template", "--dry-run")
      expect(status.success?).to be true
      expect(out).to include("/app_template")
      expect(out).to include("/analytics_template")
      expect(out.scan("db:migrate").size).to eq(2)
    end
  end

  it "db:setup-template exits 2 without databases in config" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "empty.yml")
      File.write(cfg, "{}\n")
      _out, status = polyrun("-c", cfg, "db:setup-template", "--dry-run")
      expect(status.exitstatus).to eq(2)
    end
  end

  it "db:setup-shard exits 2 when template_db is missing" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          shard_db_pattern: "app_%{shard}"
      YAML
      _out, status = polyrun("-c", cfg, "db:setup-shard", "--dry-run")
      expect(status.exitstatus).to eq(2)
    end
  end
end
