module Polyrun
  class CLI
    # +polyrun start+ only: run +prepare+ and/or Postgres template+shard DBs before parallel RSpec.
    module StartBootstrap
      private

      def start_bootstrap!(cfg, argv, config_path)
        if start_run_prepare?(cfg) && !truthy_env?("POLYRUN_START_SKIP_PREPARE")
          recipe = cfg.prepare["recipe"] || cfg.prepare[:recipe] || "default"
          Polyrun::Log.warn "polyrun start: running prepare (recipe=#{recipe})" if @verbose
          code = cmd_prepare([], config_path)
          return code if code != 0
        end

        return 0 unless start_databases_provision_wanted?(cfg) && !truthy_env?("POLYRUN_START_SKIP_DATABASES")

        dh = cfg.databases
        adapter = Polyrun::Database::UrlBuilder::ConnectionInfer.infer_adapter_name(dh)
        unless adapter == "postgresql"
          return start_non_postgresql_databases_outcome(cfg, adapter)
        end

        workers = parse_workers_from_start_argv(argv)
        Polyrun::Log.warn "polyrun start: provisioning test DBs (template + shards 0..#{workers - 1})" if @verbose
        begin
          Polyrun::Database::CloneShards.provision!(
            dh,
            workers: workers,
            rails_root: Dir.pwd,
            migrate: true,
            replace: true,
            force_drop: truthy_env?("POLYRUN_PG_DROP_FORCE"),
            dry_run: false,
            silent: !@verbose
          )
        rescue Polyrun::Error => e
          Polyrun::Log.warn "polyrun start: #{e.message}"
          return 1
        end
        0
      end

      def start_run_prepare?(cfg)
        st = cfg.start_config
        prep = cfg.prepare
        return false unless prep.is_a?(Hash) && !prep.empty?

        return false if st["prepare"] == false || st[:prepare] == false
        return true if st["prepare"] == true || st[:prepare] == true

        prepare_recipe_has_side_effects?(prep)
      end

      def prepare_recipe_has_side_effects?(prep)
        recipe = (prep["recipe"] || prep[:recipe] || "default").to_s
        return true if %w[shell assets].include?(recipe)
        return true if prep["command"] || prep[:command] || prep["commands"] || prep[:commands]

        false
      end

      def start_databases_provision_wanted?(cfg)
        st = cfg.start_config
        dh = cfg.databases
        return false unless dh.is_a?(Hash)

        template = (dh["template_db"] || dh[:template_db]).to_s
        return false if template.empty?

        return false if st["databases"] == false || st[:databases] == false

        true
      end

      def start_databases_explicitly_enabled?(cfg)
        st = cfg.start_config
        st["databases"] == true || st[:databases] == true
      end

      def start_non_postgresql_databases_outcome(cfg, adapter)
        if start_databases_explicitly_enabled?(cfg)
          Polyrun::Log.warn(
            "polyrun start: start.databases is true but databases adapter is #{adapter}; " \
            "CloneShards auto provision is PostgreSQL-only. Set start.databases: false and provision " \
            "shards yourself (for example in prepare), or use a postgresql: connection block."
          )
          return 1
        end

        Polyrun::Log.warn(
          "polyrun start: skipping database provision (adapter=#{adapter}; CloneShards is PostgreSQL-only). " \
          "Provision shards in prepare, or set start.databases: false to silence this message."
        )
        0
      end

      def parse_workers_from_start_argv(argv)
        sep = argv.index("--")
        head = sep ? argv[0...sep] : argv
        workers = env_int("POLYRUN_WORKERS", Polyrun::Config::DEFAULT_PARALLEL_WORKERS)
        i = 0
        while i < head.size
          if head[i] == "--workers" && head[i + 1]
            w = Integer(head[i + 1], exception: false)
            workers = w if w && w >= 1
            i += 2
          else
            i += 1
          end
        end
        workers.clamp(1, Polyrun::Config::MAX_PARALLEL_WORKERS)
      end

      def truthy_env?(name)
        v = ENV[name].to_s.downcase
        %w[1 true yes].include?(v)
      end
    end
  end
end
