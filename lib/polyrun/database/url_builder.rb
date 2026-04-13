require "shellwords"
require "uri"
require_relative "url_builder/connection"

module Polyrun
  module Database
    # Builds database URLs from +polyrun.yml+ +databases+ (spec2 §5.2) — no Liquid; use ENV fallbacks.
    # Use +adapter:+ or nested blocks: +postgresql+, +mysql+ / +mysql2+ / +trilogy+, +sqlserver+ / +mssql+,
    # +sqlite3+ / +sqlite+, +mongodb+ / +mongo+.
    module UrlBuilder
      module_function

      def postgres_url_for_template(databases_hash)
        url_for_template(databases_hash)
      end

      def postgres_url_for_database_name(databases_hash, database_name)
        url_for_database_name(databases_hash, database_name)
      end

      def postgres_url_for_shard(databases_hash, shard_index:, connection: nil)
        url_for_shard(databases_hash, shard_index: shard_index, connection: connection)
      end

      def url_for_template(databases_hash)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        dbname = dh["template_db"] || dh[:template_db]
        raise Polyrun::Error, "databases.template_db is required" if dbname.nil? || dbname.to_s.empty?

        url_for_database_name(dh, dbname.to_s)
      end

      def url_for_database_name(databases_hash, database_name)
        conn = Connection.resolve_connection(databases_hash)
        Connection.build_database_url(database_name.to_s, conn)
      end

      # ENV overrides so +bin/rails db:prepare+ runs once for multi-DB apps: each connection keeps its own
      # +migrations_paths+ (e.g. db/cache_migrate) instead of pointing DATABASE_URL at every template in turn.
      def template_prepare_env(databases_hash)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        pt = (dh["template_db"] || dh[:template_db]).to_s
        raise Polyrun::Error, "template_prepare_env: set databases.template_db" if pt.empty?

        out = {}
        out["DATABASE_URL"] = url_for_database_name(dh, pt)

        Array(dh["connections"] || dh[:connections]).each do |c|
          nm = (c["name"] || c[:name]).to_s
          key = (c["env_key"] || c[:env_key]).to_s.strip
          key = "DATABASE_URL_#{nm.upcase.tr("-", "_")}" if key.empty? && !nm.empty?
          next if key.empty?

          tname = (c["template_db"] || c[:template_db]).to_s
          tname = pt if tname.empty?
          out[key] = url_for_database_name(dh, tname)
        end
        out
      end

      def template_prepare_env_shell_log(databases_hash)
        template_prepare_env(databases_hash).sort.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(" ")
      end

      def unique_template_migrate_urls(databases_hash)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        seen = {}
        out = []
        pt = (dh["template_db"] || dh[:template_db]).to_s
        unless pt.empty?
          out << url_for_database_name(dh, pt)
          seen[pt] = true
        end
        Array(dh["connections"] || dh[:connections]).each do |c|
          t = (c["template_db"] || c[:template_db]).to_s
          t = pt if t.empty?
          next if t.empty?
          next if seen[t]

          out << url_for_database_name(dh, t)
          seen[t] = true
        end
        out
      end

      def shard_database_name(databases_hash, shard_index:, connection: nil)
        extract_db_name(url_for_shard(databases_hash, shard_index: shard_index, connection: connection))
      end

      def template_database_name_for(databases_hash, connection: nil)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        if connection.nil?
          return (dh["template_db"] || dh[:template_db]).to_s
        end

        c = Array(dh["connections"] || dh[:connections]).find { |x| (x["name"] || x[:name]).to_s == connection.to_s }
        return "" unless c

        (c["template_db"] || c[:template_db] || dh["template_db"] || dh[:template_db]).to_s
      end

      def shard_database_plan(databases_hash, shard_index:)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        rows = []
        primary_shard = shard_database_name(dh, shard_index: shard_index, connection: nil)
        primary_tmpl = template_database_name_for(dh, connection: nil)
        if !primary_shard.empty? && !primary_tmpl.empty?
          rows << {new_db: primary_shard, template_db: primary_tmpl}
        end

        Array(dh["connections"] || dh[:connections]).each do |c|
          nm = (c["name"] || c[:name]).to_s
          next if nm.empty?

          sname = shard_database_name(dh, shard_index: shard_index, connection: nm)
          tname = template_database_name_for(dh, connection: nm)
          rows << {new_db: sname, template_db: tname} if !sname.empty? && !tname.empty?
        end
        rows
      end

      def url_for_shard(databases_hash, shard_index:, connection: nil)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        conn = Connection.resolve_connection(dh)
        pattern =
          if connection
            conns = dh["connections"] || dh[:connections] || []
            c = Array(conns).find { |x| (x["name"] || x[:name]).to_s == connection.to_s }
            (c && (c["shard_db_pattern"] || c[:shard_db_pattern])) || dh["shard_db_pattern"]
          else
            dh["shard_db_pattern"] || dh[:shard_db_pattern]
          end
        pattern ||= "app_test_%{shard}"

        dbname = pattern.to_s.gsub("%{shard}", Integer(shard_index).to_s).gsub("%<shard>d", format("%d", Integer(shard_index)))
        Connection.build_database_url(dbname, conn)
      end

      def env_exports_for_databases(databases_hash, shard_index:)
        dh = databases_hash.is_a?(Hash) ? databases_hash : {}
        out = {}
        primary_url = url_for_shard(dh, shard_index: shard_index)
        out["DATABASE_URL"] = primary_url
        out["TEST_DB_NAME"] = extract_db_name(primary_url)

        conns = dh["connections"] || dh[:connections] || []
        Array(conns).each do |c|
          name = (c["name"] || c[:name]).to_s
          next if name.empty?

          u = url_for_shard(dh, shard_index: shard_index, connection: name)
          key = (c["env_key"] || c[:env_key]).to_s.strip
          key = "DATABASE_URL_#{name.upcase.tr("-", "_")}" if key.empty?
          out[key] = u
        end
        out
      end

      def extract_db_name(url)
        s = url.to_s
        return s.sub(/\Asqlite3:/i, "") if s.match?(/\Asqlite3:/i)

        URI.parse(s).path.delete_prefix("/").split("?", 2).first
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
