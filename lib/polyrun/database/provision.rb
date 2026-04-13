require "open3"
require "shellwords"

module Polyrun
  module Database
    # PostgreSQL-only provisioning via +psql+ / +createdb+ (spec2 §5.3). No +pg+ gem.
    # For other adapters, use Rails tasks or vendor CLIs; +Polyrun::Database::UrlBuilder+ still emits +DATABASE_URL+ for supported schemes.
    module Provision
      module_function

      def quote_ident(name)
        '"' + name.to_s.gsub('"', '""') + '"'
      end

      # +DROP DATABASE IF EXISTS name;+ — maintenance DB +postgres+ (or +maintenance_db+).
      def drop_database_if_exists!(database:, host: nil, port: nil, username: nil, maintenance_db: "postgres", force: false)
        host ||= ENV["PGHOST"] || "localhost"
        port ||= ENV["PGPORT"] || "5432"
        username ||= ENV["PGUSER"] || "postgres"

        sql =
          if force
            "DROP DATABASE IF EXISTS #{quote_ident(database)} WITH (FORCE);"
          else
            "DROP DATABASE IF EXISTS #{quote_ident(database)};"
          end
        cmd = ["psql", "-U", username, "-h", host, "-p", port.to_s, "-d", maintenance_db, "-v", "ON_ERROR_STOP=1", "-c", sql]
        _out, err, st = Open3.capture3(*cmd)
        raise Polyrun::Error, "drop database failed: #{err}" unless st.success?

        true
      end

      # CREATE DATABASE new_db TEMPLATE template_db — connects to maintenance DB +postgres+.
      def create_database_from_template!(new_db:, template_db:, host: nil, port: nil, username: nil, maintenance_db: "postgres")
        host ||= ENV["PGHOST"] || "localhost"
        port ||= ENV["PGPORT"] || "5432"
        username ||= ENV["PGUSER"] || "postgres"

        sql = "CREATE DATABASE #{quote_ident(new_db)} TEMPLATE #{quote_ident(template_db)};"
        cmd = ["psql", "-U", username, "-h", host, "-p", port.to_s, "-d", maintenance_db, "-v", "ON_ERROR_STOP=1", "-c", sql]
        _out, err, st = Open3.capture3(*cmd)
        raise Polyrun::Error, "create database failed: #{err}" unless st.success?

        true
      end

      # Runs +bin/rails db:prepare+ with merged ENV (+DATABASE_URL+ for primary, +CACHE_DATABASE_URL+, etc.).
      # Multi-DB Rails apps must pass all template URLs in one invocation so each DB uses its own +migrations_paths+.
      # Uses +db:prepare+ (not +db:migrate+ alone) so empty template databases load +schema.rb+ first;
      # apps that squash or archive migrations and keep only incremental files need that path.
      def prepare_template!(rails_root:, env:, silent: true)
        exe = File.join(rails_root, "bin", "rails")
        raise Polyrun::Error, "Provision: missing #{exe}" unless File.executable?(exe)

        child_env = ENV.to_h.merge(env)
        child_env["RAILS_ENV"] ||= ENV["RAILS_ENV"] || "test"
        rails_out, err, st = Open3.capture3(child_env, exe, "db:prepare", chdir: rails_root)
        Polyrun::Log.warn err if !silent && !err.to_s.empty?
        unless st.success?
          msg = +"db:prepare failed"
          msg << "\n--- stderr ---\n#{err}" unless err.to_s.strip.empty?
          # Rails often prints the first migration/SQL error on stdout; stderr may only show InFailedSqlTransaction.
          msg << "\n--- stdout ---\n#{rails_out}" unless rails_out.to_s.strip.empty?
          raise Polyrun::Error, msg
        end

        true
      end
    end
  end
end
