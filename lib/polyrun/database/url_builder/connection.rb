require_relative "connection/infer"
require_relative "connection/url_builders"

module Polyrun
  module Database
    module UrlBuilder
      # Adapter detection, ENV fallbacks, and URL string construction (Rails +DATABASE_URL+ conventions).
      module Connection
        module_function

        def resolve_connection(databases_hash)
          dh = normalize_hash(databases_hash)
          profile = connection_profile(dh)
          blk = merged_connection_block(dh, profile)
          scheme = profile[:scheme]
          host = (blk["host"] || env_first(profile[:env_host]) || profile[:default_host]).to_s
          port = (blk["port"] || env_first(profile[:env_port]) || profile[:default_port]).to_s
          user = (blk["username"] || blk["user"] || env_first(profile[:env_user]) || profile[:default_user]).to_s
          password = blk["password"] || env_first(profile[:env_password])

          {
            scheme: scheme,
            host: host,
            port: port,
            user: user,
            password: password
          }
        end

        def build_database_url(database, conn)
          scheme = conn[:scheme].to_s
          host = conn[:host].to_s
          port = conn[:port].to_s
          user = conn[:user].to_s
          password = conn[:password]
          db = database.to_s

          case scheme
          when "postgres"
            ConnectionUrlBuilders.build_url_authority("postgres", host, port, user, password, db)
          when "mysql2", "trilogy"
            ConnectionUrlBuilders.build_url_authority(scheme, host, port, user, password, db)
          when "sqlserver"
            ConnectionUrlBuilders.build_url_authority("sqlserver", host, port, user, password, db)
          when "mongodb"
            ConnectionUrlBuilders.build_mongodb_url(host, port, user, password, db)
          when "sqlite3"
            ConnectionUrlBuilders.build_sqlite_url(db)
          else
            raise Polyrun::Error, "unsupported URL scheme: #{scheme.inspect}"
          end
        end

        def connection_profile(dh)
          name = ConnectionInfer.infer_adapter_name(dh)
          case name
          when "postgresql"
            {
              scheme: "postgres",
              nested_key: "postgresql",
              default_host: "localhost",
              default_port: "5432",
              default_user: "postgres",
              env_host: %w[PGHOST],
              env_port: %w[PGPORT],
              env_user: %w[PGUSER],
              env_password: %w[PGPASSWORD]
            }
          when "mysql2"
            nested_mysql_key(dh)
          when "trilogy"
            {
              scheme: "trilogy",
              nested_key: "trilogy",
              default_host: "localhost",
              default_port: "3306",
              default_user: "root",
              env_host: %w[MYSQL_HOST MYSQL_ADDRESS TRILOGY_HOST],
              env_port: %w[MYSQL_PORT MYSQL_TCP_PORT TRILOGY_PORT],
              env_user: %w[MYSQL_USER MYSQL_USERNAME TRILOGY_USER],
              env_password: %w[MYSQL_PASSWORD MYSQL_PWD TRILOGY_PASSWORD]
            }
          when "sqlserver"
            nested =
              if ConnectionInfer.nested_hash?(dh, "sqlserver")
                "sqlserver"
              else
                "mssql"
              end
            {
              scheme: "sqlserver",
              nested_key: nested,
              default_host: "localhost",
              default_port: "1433",
              default_user: "sa",
              env_host: %w[SQLSERVER_HOST MSSQL_HOST TDS_HOST],
              env_port: %w[SQLSERVER_PORT MSSQL_PORT TDS_PORT],
              env_user: %w[SQLSERVER_USER MSSQL_USER SA_USER],
              env_password: %w[SQLSERVER_PASSWORD MSSQL_PASSWORD SA_PASSWORD]
            }
          when "sqlite3"
            nested =
              if ConnectionInfer.nested_hash?(dh, "sqlite3")
                "sqlite3"
              else
                "sqlite"
              end
            {
              scheme: "sqlite3",
              nested_key: nested,
              default_host: "",
              default_port: "",
              default_user: "",
              env_host: [],
              env_port: [],
              env_user: [],
              env_password: []
            }
          when "mongodb"
            nested_mongo_key(dh)
          else
            raise Polyrun::Error, "unsupported databases.adapter: #{name.inspect}"
          end
        end

        def nested_mysql_key(dh)
          nested =
            if ConnectionInfer.nested_hash?(dh, "mysql2")
              "mysql2"
            else
              "mysql"
            end
          {
            scheme: "mysql2",
            nested_key: nested,
            default_host: "localhost",
            default_port: "3306",
            default_user: "root",
            env_host: %w[MYSQL_HOST MYSQL_ADDRESS],
            env_port: %w[MYSQL_PORT MYSQL_TCP_PORT],
            env_user: %w[MYSQL_USER MYSQL_USERNAME],
            env_password: %w[MYSQL_PASSWORD MYSQL_PWD]
          }
        end

        def nested_mongo_key(dh)
          nested =
            if ConnectionInfer.nested_hash?(dh, "mongodb")
              "mongodb"
            else
              "mongo"
            end
          {
            scheme: "mongodb",
            nested_key: nested,
            default_host: "localhost",
            default_port: "27017",
            default_user: "",
            env_host: %w[MONGO_HOST MONGODB_HOST],
            env_port: %w[MONGO_PORT MONGODB_PORT],
            env_user: %w[MONGO_USER MONGODB_USER],
            env_password: %w[MONGO_PASSWORD MONGODB_PASSWORD]
          }
        end

        def merged_connection_block(dh, profile)
          nk = profile[:nested_key]
          nested = dh[nk].is_a?(Hash) ? normalize_hash(dh[nk]) : {}
          top = dh.slice("host", "port", "username", "user", "password").transform_keys(&:to_s)
          nested.merge(top)
        end

        def normalize_hash(h)
          h.is_a?(Hash) ? h.transform_keys(&:to_s) : {}
        end

        def env_first(keys)
          Array(keys).each do |k|
            v = ENV[k]
            return v if present?(v)
          end
          nil
        end

        def present?(s)
          !s.nil? && !s.to_s.empty?
        end
      end
    end
  end
end
