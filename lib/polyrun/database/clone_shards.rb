module Polyrun
  module Database
    # Prepare canonical template DBs (+bin/rails db:prepare+ — schema load on empty DB, then migrate) then create per-shard databases (PostgreSQL +CREATE DATABASE … TEMPLATE …+).
    # Other ActiveRecord adapters (MySQL, SQL Server, SQLite, …) are not automated here—use +polyrun env+ URLs with your own +db:*+ scripts.
    # Replaces shell loops like +dropdb+ / +createdb -T+ when +polyrun.yml databases:+ lists primary + +connections+.
    module CloneShards
      module_function

      # See +provision!+ on the singleton class for options.
      def provision!(databases_hash, workers:, rails_root:, migrate: true, replace: true, force_drop: false, dry_run: false, silent: true)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        workers = Integer(workers)
        raise Polyrun::Error, "workers must be >= 1" if workers < 1

        rails_root = File.expand_path(rails_root)

        migrate_canonical_databases!(dh, rails_root, dry_run, silent) if migrate
        create_shards_from_plan!(dh, workers, replace, force_drop, dry_run)
        true
      end

      def migrate_canonical_databases!(dh, rails_root, dry_run, silent)
        pt = (dh["template_db"] || dh[:template_db]).to_s
        if pt.empty?
          raise Polyrun::Error, "CloneShards: set databases.template_db (and optional connections[].template_db)"
        end

        if dry_run
          log = UrlBuilder.template_prepare_env_shell_log(dh)
          Polyrun::Log.warn "would: RAILS_ENV=test #{log} bin/rails db:prepare"
        else
          child_env = ENV.to_h.merge(UrlBuilder.template_prepare_env(dh))
          child_env["RAILS_ENV"] ||= ENV["RAILS_ENV"] || "test"
          Provision.prepare_template!(rails_root: rails_root, env: child_env, silent: silent)
        end
      end
      private_class_method :migrate_canonical_databases!

      def create_shards_from_plan!(dh, workers, replace, force_drop, dry_run)
        workers.times do |shard_index|
          plan = UrlBuilder.shard_database_plan(dh, shard_index: shard_index)
          if plan.empty?
            raise Polyrun::Error, "CloneShards: empty shard plan for shard_index=#{shard_index}"
          end

          plan.each { |row| create_one_shard!(row, replace, force_drop, dry_run) }
        end
      end
      private_class_method :create_shards_from_plan!

      def create_one_shard!(row, replace, force_drop, dry_run)
        new_db = row[:new_db].to_s
        tmpl = row[:template_db].to_s
        if dry_run
          Polyrun::Log.warn "would: DROP DATABASE IF EXISTS #{new_db}" if replace
          Polyrun::Log.warn "would: CREATE DATABASE #{new_db} TEMPLATE #{tmpl}"
          return
        end

        Provision.drop_database_if_exists!(database: new_db, force: force_drop) if replace
        Provision.create_database_from_template!(new_db: new_db, template_db: tmpl)
      end
      private_class_method :create_one_shard!
    end
  end
end
