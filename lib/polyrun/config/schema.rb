module Polyrun
  class Config
    # Lightweight top-level key checks for +polyrun validate+.
    module Schema
      KNOWN_TOP_LEVEL = %w[
        version
        partition
        prepare
        coverage
        databases
        start
        hooks
        reporting
        workers
        suites
      ].freeze

      module_function

      def validate(cfg)
        raw = cfg.raw
        return {ok: true, messages: ["polyrun validate: no config file found (empty defaults)"]} if cfg.path.nil?

        unless raw.is_a?(Hash)
          return {ok: false, messages: ["polyrun validate: config root must be a mapping"]}
        end

        unknown = raw.keys.map(&:to_s) - KNOWN_TOP_LEVEL
        messages = unknown.sort.map { |k| "polyrun validate: unknown top-level key #{k.inspect}" }
        {ok: messages.empty?, messages: messages}
      end
    end
  end
end
