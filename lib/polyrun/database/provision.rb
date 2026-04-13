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

      # Runs +bin/rails db:migrate+ with DATABASE_URL set (template DB already exists).
      def migrate_template!(rails_root:, database_url:, silent: true)
        exe = File.join(rails_root, "bin", "rails")
        raise Polyrun::Error, "Provision: missing #{exe}" unless File.executable?(exe)

        env = ENV.to_h.merge("DATABASE_URL" => database_url, "RAILS_ENV" => ENV["RAILS_ENV"] || "test")
        _out, err, st = Open3.capture3(env, exe, "db:migrate", chdir: rails_root)
        Polyrun::Log.warn err if !silent && !err.to_s.empty?
        raise Polyrun::Error, "db:migrate failed: #{err}" unless st.success?

        true
      end
    end
  end
end
