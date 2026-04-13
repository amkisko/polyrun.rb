require "spec_helper"

RSpec.describe Polyrun::CLI do
  let(:cli) { described_class.new }

  describe "start bootstrap helpers (private)" do
    it "parses --workers from argv head" do
      expect(cli.send(:parse_workers_from_start_argv, %w[--workers 3 -- bundle exec rspec])).to eq(3)
    end

    it "defaults workers from POLYRUN_WORKERS" do
      old = ENV["POLYRUN_WORKERS"]
      ENV["POLYRUN_WORKERS"] = "7"
      expect(cli.send(:parse_workers_from_start_argv, ["--", "x"])).to eq(7)
    ensure
      old ? ENV.store("POLYRUN_WORKERS", old) : ENV.delete("POLYRUN_WORKERS")
    end

    it "clamps workers to max" do
      expect(cli.send(:parse_workers_from_start_argv, %w[--workers 99 --])).to eq(10)
    end

    it "truthy_env? detects POLYRUN flags" do
      expect(cli.send(:truthy_env?, "POLYRUN_X")).to be false
      ENV["POLYRUN_X"] = "yes"
      expect(cli.send(:truthy_env?, "POLYRUN_X")).to be true
    ensure
      ENV.delete("POLYRUN_X")
    end

    it "prepare_recipe_has_side_effects? for shell and assets" do
      expect(cli.send(:prepare_recipe_has_side_effects?, {"recipe" => "shell"})).to be true
      expect(cli.send(:prepare_recipe_has_side_effects?, {"recipe" => "assets"})).to be true
    end

    it "prepare_recipe_has_side_effects? when command present" do
      expect(cli.send(:prepare_recipe_has_side_effects?, {"recipe" => "default", "command" => "echo"})).to be true
    end

    it "prepare_recipe_has_side_effects? is false for default recipe" do
      expect(cli.send(:prepare_recipe_has_side_effects?, {"recipe" => "default"})).to be false
    end

    it "start_run_database_provision? respects start.databases" do
      cfg = Polyrun::Config.new(path: nil, raw: {
        "start" => {"databases" => false},
        "databases" => {"template_db" => "t"}
      })
      expect(cli.send(:start_run_database_provision?, cfg)).to be false
    end

    it "start_run_database_provision? is true when start.databases true" do
      cfg = Polyrun::Config.new(path: nil, raw: {
        "start" => {"databases" => true},
        "databases" => {"template_db" => "t"}
      })
      expect(cli.send(:start_run_database_provision?, cfg)).to be true
    end

    it "start_run_prepare? is false when prepare empty" do
      cfg = Polyrun::Config.new(path: nil, raw: {"start" => {}, "prepare" => {}})
      expect(cli.send(:start_run_prepare?, cfg)).to be false
    end

    it "start_run_prepare? is false when start.prepare false" do
      cfg = Polyrun::Config.new(path: nil, raw: {
        "start" => {"prepare" => false},
        "prepare" => {"recipe" => "shell", "command" => "echo"}
      })
      expect(cli.send(:start_run_prepare?, cfg)).to be false
    end

    it "start_run_prepare? is true when start.prepare true" do
      cfg = Polyrun::Config.new(path: nil, raw: {
        "start" => {"prepare" => true},
        "prepare" => {"recipe" => "default"}
      })
      expect(cli.send(:start_run_prepare?, cfg)).to be true
    end
  end
end
