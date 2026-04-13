require "optparse"

module Polyrun
  class CLI
    module DatabaseCommands
      private

      def cmd_db_setup_template(argv, config_path)
        dry = false
        rails_root = Dir.pwd
        parser = OptionParser.new do |opts|
          opts.on("--dry-run", "Print only") { dry = true }
          opts.on("--rails-root PATH", String) { |v| rails_root = v }
        end
        parser.parse!(argv)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        dh = cfg.databases
        if !dh.is_a?(Hash) || dh.empty?
          Polyrun::Log.warn "db:setup-template: configure databases: in polyrun.yml"
          return 2
        end

        begin
          te = Polyrun::Database::UrlBuilder.template_prepare_env(dh)
        rescue Polyrun::Error => e
          Polyrun::Log.warn "db:setup-template: #{e.message}"
          return 2
        end

        if dry
          log = Polyrun::Database::UrlBuilder.template_prepare_env_shell_log(dh)
          Polyrun::Log.warn "would: RAILS_ENV=test #{log} bin/rails db:prepare"
          return 0
        end

        child_env = ENV.to_h.merge(te)
        child_env["RAILS_ENV"] ||= ENV["RAILS_ENV"] || "test"
        Polyrun::Database::Provision.prepare_template!(
          rails_root: File.expand_path(rails_root),
          env: child_env,
          silent: !@verbose
        )
        0
      end

      def cmd_db_setup_shard(argv, config_path)
        dry = false
        parser = OptionParser.new do |opts|
          opts.on("--dry-run", "Print only") { dry = true }
        end
        parser.parse!(argv)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        dh = cfg.databases
        if !dh.is_a?(Hash) || dh.empty?
          Polyrun::Log.warn "db:setup-shard: configure databases: in polyrun.yml"
          return 2
        end

        shard = resolve_shard_index(pc)
        template = dh["template_db"] || dh[:template_db]
        if !template
          Polyrun::Log.warn "db:setup-shard: set databases.template_db"
          return 2
        end

        plan = Polyrun::Database::UrlBuilder.shard_database_plan(dh, shard_index: shard)
        if plan.empty?
          Polyrun::Log.warn "db:setup-shard: could not derive shard database names from polyrun.yml"
          return 2
        end

        if dry
          plan.each do |row|
            Polyrun::Log.warn "would: CREATE DATABASE #{row[:new_db]} TEMPLATE #{row[:template_db]}"
          end
          return 0
        end

        plan.each do |row|
          Polyrun::Database::Provision.create_database_from_template!(
            new_db: row[:new_db],
            template_db: row[:template_db].to_s
          )
        end
        0
      end

      # Migrate all template DBs + create every shard database (primary + +connections+).
      def cmd_db_clone_shards(argv, config_path)
        dry = false
        migrate = true
        replace = true
        force_drop = false
        rails_root = Dir.pwd
        workers = env_int("POLYRUN_WORKERS", 5)

        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun db:clone-shards [--workers N] [--rails-root PATH] [--dry-run] [--no-migrate] [--no-replace] [--force-drop]"
          opts.on("--workers N", Integer) { |v| workers = v }
          opts.on("--dry-run", "Print only") { dry = true }
          opts.on("--rails-root PATH", String) { |v| rails_root = v }
          opts.on("--no-migrate", "Skip db:prepare on template databases") { migrate = false }
          opts.on("--no-replace", "Skip DROP DATABASE before CREATE (fail if shard DB exists)") { replace = false }
          opts.on("--force-drop", "DROP DATABASE … WITH (FORCE) (PostgreSQL 13+)") { force_drop = true }
        end
        parser.parse!(argv)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        dh = cfg.databases
        if !dh.is_a?(Hash) || dh.empty?
          Polyrun::Log.warn "db:clone-shards: configure databases: in polyrun.yml"
          return 2
        end

        workers = workers.clamp(1, 10)

        Polyrun::Database::CloneShards.provision!(
          dh,
          workers: workers,
          rails_root: File.expand_path(rails_root),
          migrate: migrate,
          replace: replace,
          force_drop: force_drop,
          dry_run: dry,
          silent: !@verbose
        )
        0
      rescue Polyrun::Error => e
        Polyrun::Log.warn "db:clone-shards: #{e.message}"
        1
      end
    end
  end
end
