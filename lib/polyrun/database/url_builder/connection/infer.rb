module Polyrun
  module Database
    module UrlBuilder
      # Infer canonical adapter name from +polyrun.yml+ +databases:+ hash.
      module ConnectionInfer
        module_function

        INFER_ADAPTER_FROM_NESTED = [
          %w[postgresql postgresql],
          %w[trilogy trilogy],
          %w[mysql2 mysql2],
          %w[mysql mysql2],
          %w[sqlserver sqlserver],
          %w[mssql sqlserver],
          %w[sqlite3 sqlite3],
          %w[sqlite sqlite3],
          %w[mongodb mongodb],
          %w[mongo mongodb]
        ].freeze

        def infer_adapter_name(dh)
          explicit = (dh["adapter"] || dh[:adapter]).to_s.strip.downcase
          explicit = normalize_adapter_alias(explicit)
          return explicit unless explicit.empty?

          INFER_ADAPTER_FROM_NESTED.each do |key, name|
            return name if nested_hash?(dh, key)
          end
          "postgresql"
        end

        def normalize_adapter_alias(name)
          case name
          when "postgres", "pg" then "postgresql"
          when "mysql" then "mysql2"
          when "mongo" then "mongodb"
          when "mssql" then "sqlserver"
          when "sqlite" then "sqlite3"
          else name
          end
        end

        def nested_hash?(dh, key)
          dh[key].is_a?(Hash) || dh[key.to_sym].is_a?(Hash)
        end
      end
    end
  end
end
