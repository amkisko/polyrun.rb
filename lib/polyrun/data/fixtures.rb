require "yaml"

module Polyrun
  module Data
    # Declarative YAML fixture batches (**YAML → table → rows**).
    # Polyrun does **not** ship a seed/register loader DSL—only **stdlib YAML** + iteration helpers.
    # Typical layout: +spec/fixtures/polyrun/*.yml+ with top-level keys = table names.
    #
    #   users:
    #     - name: Ada
    #       email: ada@example.com
    module Fixtures
      module_function

      def load_yaml(path)
        YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
      end

      # Returns { "batch_name" => { "table" => [rows] } } for every +.yml+ under +dir+ (recursive).
      def load_directory(dir)
        Dir.glob(File.join(dir, "**", "*.yml")).sort.each_with_object({}) do |path, acc|
          key = File.basename(path, ".*")
          acc[key] = load_yaml(path)
        end
      end

      # Iterates each table in a single batch hash. Skips keys starting with "_".
      def each_table(batch)
        return enum_for(:each_table, batch) unless block_given?

        batch.each do |table, rows|
          t = table.to_s
          next if t.start_with?("_")

          raise Polyrun::Error, "fixtures: #{t} must be an Array of rows" unless rows.is_a?(Array)

          yield(t, rows)
        end
      end

      # Loads all batches from +dir+ and yields (batch_name, table, rows).
      def each_table_in_directory(dir)
        return enum_for(:each_table_in_directory, dir) unless block_given?

        load_directory(dir).each do |batch_name, batch|
          each_table(batch) do |table, rows|
            yield(batch_name, table, rows)
          end
        end
      end

      # Bulk insert YAML rows via ActiveRecord (batch load optimization). Requires ActiveRecord
      # and a +connection+ that responds to +insert_all(table_name, records)+ (Rails 6+).
      def apply_insert_all!(batch, connection: nil)
        unless defined?(ActiveRecord::Base)
          raise Polyrun::Error, "Fixtures.apply_insert_all! requires ActiveRecord"
        end

        conn = connection || ActiveRecord::Base.connection
        each_table(batch) do |table, rows|
          next if rows.empty?

          conn.insert_all(table, rows)
        end
      end
    end
  end
end
