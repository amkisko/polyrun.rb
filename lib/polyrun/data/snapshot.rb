require "fileutils"
require "open3"

module Polyrun
  module Data
    # PostgreSQL data snapshots via +pg_dump+ / +psql+ (no +pg+ gem). Configure with ENV or explicit args.
    # Non-Postgres adapters: use native backup/export tools; not covered here.
    module SqlSnapshot
      module_function

      def default_connection
        {
          host: ENV["PGHOST"],
          port: ENV["PGPORT"],
          username: ENV["PGUSER"] || ENV["USER"],
          database: ENV["PGDATABASE"]
        }
      end

      # Writes data-only SQL to +root+/spec/fixtures/sql_snapshots/<name>.sql
      def create!(name, root:, database: nil, username: nil, host: nil, port: nil)
        database ||= default_connection[:database] or raise Polyrun::Error, "SqlSnapshot: set database: or PGDATABASE"
        username ||= default_connection[:username]
        path = File.join(root, "spec", "fixtures", "sql_snapshots", "#{name}.sql")
        FileUtils.mkdir_p(File.dirname(path))

        cmd = ["pg_dump", "--data-only", "-U", username]
        cmd += ["-h", host] if host && !host.to_s.empty?
        cmd += ["-p", port.to_s] if port && !port.to_s.empty?
        cmd << database

        out, err, st = Open3.capture3(*cmd)
        raise Polyrun::Error, "pg_dump failed: #{err}" unless st.success?

        File.write(path, out)
        path
      end

      # Truncates listed tables (if any), then loads snapshot SQL. +tables+ optional; if nil and ActiveRecord
      # is loaded, uses +connection.tables+.
      def load!(name, root:, database: nil, username: nil, host: nil, port: nil, tables: nil)
        database ||= default_connection[:database] or raise Polyrun::Error, "SqlSnapshot: set database: or PGDATABASE"
        username ||= default_connection[:username]
        path = File.join(root, "spec", "fixtures", "sql_snapshots", "#{name}.sql")
        raise Polyrun::Error, "SqlSnapshot: missing #{path}" unless File.file?(path)

        if tables.nil? && defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
          tables = ActiveRecord::Base.connection.tables
        end
        tables ||= []

        psql = sql_snapshot_psql_base(username, database, host, port)
        sql_snapshot_truncate_tables!(psql, tables) if tables.any?
        sql_snapshot_load_file!(psql, path)
        true
      end

      def sql_snapshot_psql_base(username, database, host, port)
        psql = ["psql", "-U", username, "-d", database]
        psql += ["-h", host] if host && !host.to_s.empty?
        psql += ["-p", port.to_s] if port && !port.to_s.empty?
        psql
      end

      def sql_snapshot_truncate_tables!(psql, tables)
        quoted = tables.map { |t| %("#{t.gsub('"', '""')}") }.join(", ")
        trunc = "TRUNCATE TABLE #{quoted} CASCADE;"
        _trunc_out, err, st = Open3.capture3(*psql, "-v", "ON_ERROR_STOP=1", "-c", trunc)
        raise Polyrun::Error, "psql truncate failed: #{err}" unless st.success?
      end

      def sql_snapshot_load_file!(psql, path)
        _load_out, err, st = Open3.capture3(
          *psql,
          "-v", "ON_ERROR_STOP=1",
          "-c", "SET session_replication_role = 'replica';",
          "-f", path,
          "-c", "SET session_replication_role = 'origin';"
        )
        raise Polyrun::Error, "psql load failed: #{err}" unless st.success?
      end
    end
  end
end
