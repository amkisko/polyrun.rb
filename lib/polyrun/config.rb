require "yaml"

module Polyrun
  # Loads polyrun.yml (or path from POLYRUN_CONFIG / --config).
  class Config
    DEFAULT_FILENAMES = %w[polyrun.yml config/polyrun.yml].freeze

    # Parallel worker defaults (+run-shards+, +POLYRUN_WORKERS+); single source with {Resolver} and {Effective}.
    DEFAULT_PARALLEL_WORKERS = 5
    MAX_PARALLEL_WORKERS = 10

    attr_reader :path, :raw

    def self.load(path: nil)
      path = resolve_path(path)
      raw =
        if path && File.file?(path)
          YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true) || {}
        else
          {}
        end
      new(path: path, raw: raw)
    end

    def self.resolve_path(explicit)
      return File.expand_path(explicit) if explicit && !explicit.empty?

      DEFAULT_FILENAMES.each do |name|
        full = File.expand_path(name, Dir.pwd)
        return full if File.file?(full)
      end
      nil
    end

    def initialize(path:, raw:)
      @path = path
      @raw = raw.freeze
    end

    def partition
      raw["partition"] || raw[:partition] || {}
    end

    def prepare
      raw["prepare"] || raw[:prepare] || {}
    end

    def coverage
      raw["coverage"] || raw[:coverage] || {}
    end

    def databases
      raw["databases"] || raw[:databases] || {}
    end

    # Optional +start:+ block: +prepare+ / +databases+ booleans override auto-detection for +polyrun start+.
    def start_config
      raw["start"] || raw[:start] || {}
    end

    def version
      raw["version"] || raw[:version]
    end

    # Optional +hooks:+ block for +run-shards+ / +parallel-rspec+ / +ci-shard-*+ (see {Hooks}).
    def hooks
      raw["hooks"] || raw[:hooks] || {}
    end
  end
end

require_relative "config/resolver"
require_relative "config/effective"
