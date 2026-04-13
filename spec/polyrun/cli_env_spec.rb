require "spec_helper"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "rbconfig"

RSpec.describe Polyrun::CLI do
  it "prints env exports" do
    out, status = polyrun("env", "--shard", "2", "--total", "8")
    expect(status.success?).to be true
    expect(out).to include("POLYRUN_SHARD_INDEX=2")
    expect(out).to include("POLYRUN_SHARD_TOTAL=8")
    expect(out).to include("TEST_ENV_NUMBER=3")
  end

  it "env with polyrun.yml databases exports DATABASE_URL and TEST_DB_NAME" do
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, "polyrun.yml")
      File.write(cfg, <<~YAML)
        databases:
          template_db: app_tpl
          shard_db_pattern: "myapp_test_%{shard}"
          postgresql:
            host: localhost
            port: "5432"
            username: postgres
      YAML
      out, status = polyrun("-c", cfg, "env", "--shard", "1", "--total", "4")
      expect(status.success?).to be true
      expect(out).to include("export DATABASE_URL=")
      expect(out).to include("myapp_test_1")
      expect(out).to include("export TEST_DB_NAME=myapp_test_1")
    end
  end
end
