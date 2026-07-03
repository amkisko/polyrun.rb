require "yaml"

module Polyrun
  module SpecQuality
    # Loads +config/polyrun_spec_quality.yml+ and +ENV+ overrides.
    module Config
      DEFAULT_CONFIG_RELATIVE = File.join("config", "polyrun_spec_quality.yml").freeze

      DEFAULTS = {
        "track_under" => %w[lib app],
        "min_line_churn" => 50,
        "min_query_count" => 20,
        "hot_line_example_overlap" => 10,
        "strict" => false,
        "sample" => 1.0,
        "ignore_examples" => [],
        "ignore_paths" => [],
        "ignore_query_patterns" => [],
        "profile" => %w[cpu mem],
        "sql_counter" => false,
        "minimum_unique_lines_per_example" => nil,
        "max_zero_hit_examples" => nil,
        "max_hot_line_overlap" => nil
      }.freeze

      module_function

      def enabled?(env = ENV)
        return false if disabled?(env)

        truthy?(env["POLYRUN_SPEC_QUALITY"]) || truthy?(env["POLYRUN_SPEC_QUALITY_FRAGMENTS"])
      end

      def disabled?(env = ENV)
        truthy?(env["POLYRUN_SPEC_QUALITY_DISABLE"])
      end

      def load(root:, config_path: nil, env: ENV, **overrides)
        root = File.expand_path(root)
        file_cfg = load_yaml(root, config_path)
        merged = DEFAULTS.merge(stringify_keys(file_cfg))
        apply_env!(merged, env)
        merged.merge!(stringify_keys(overrides).transform_keys(&:to_s))
        merged["root"] = root
        merged["strict"] = resolve_strict(merged, env)
        merged["sample"] = resolve_sample(merged, env)
        normalize_config!(merged)
        merged
      end

      def load_yaml(root, config_path)
        path = config_path || File.join(root, DEFAULT_CONFIG_RELATIVE)
        path = File.expand_path(path)
        return {} unless File.file?(path)

        data = YAML.load_file(path)
        data.is_a?(Hash) ? data : {}
      end

      def apply_env!(cfg, env)
        cfg["strict"] = true if truthy?(env["POLYRUN_SPEC_QUALITY_STRICT"])
        if env.key?("POLYRUN_SPEC_QUALITY_SAMPLE")
          cfg["sample"] = Float(env["POLYRUN_SPEC_QUALITY_SAMPLE"])
        end
        if env.key?("POLYRUN_SPEC_QUALITY_SQL_COUNTER")
          cfg["sql_counter"] = truthy?(env["POLYRUN_SPEC_QUALITY_SQL_COUNTER"])
        end
        prof = env["POLYRUN_SPEC_QUALITY_PROFILE"]
        cfg["profile"] = prof.split(",").map(&:strip).reject(&:empty?) if prof && !prof.strip.empty?
      end

      def resolve_strict(cfg, env)
        return true if truthy?(env["POLYRUN_SPEC_QUALITY_STRICT"])

        cfg["strict"] == true || truthy?(cfg["strict"])
      end

      def resolve_sample(cfg, env)
        v = cfg["sample"]
        f = v.is_a?(Numeric) ? v.to_f : Float(v)
        f.clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        1.0
      end

      # rubocop:disable Metrics/AbcSize -- config key normalization
      def normalize_config!(cfg)
        cfg["track_under"] = Array(cfg["track_under"]).map(&:to_s).reject(&:empty?)
        cfg["track_under"] = %w[lib] if cfg["track_under"].empty?
        cfg["ignore_examples"] = Array(cfg["ignore_examples"]).map(&:to_s)
        cfg["ignore_paths"] = Array(cfg["ignore_paths"]).map(&:to_s)
        cfg["ignore_query_patterns"] = Array(cfg["ignore_query_patterns"]).map(&:to_s)
        cfg["profile"] = Array(cfg["profile"]).map(&:to_s).reject(&:empty?)
        %w[min_line_churn min_query_count hot_line_example_overlap].each do |k|
          cfg[k] = Integer(cfg[k]) if cfg[k]
        end
      end
      # rubocop:enable Metrics/AbcSize

      def ignored_example?(location, ignore_examples)
        loc = location.to_s
        return false if loc.empty?

        Array(ignore_examples).any? do |pat|
          if pat.start_with?("/") && pat.end_with?("/") && pat.size > 2
            loc.match?(Regexp.new(pat[1..-2]))
          else
            loc.include?(pat)
          end
        rescue RegexpError
          loc.include?(pat)
        end
      end

      def stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify_keys(v) }
        when Array
          obj.map { |e| stringify_keys(e) }
        else
          obj
        end
      end

      def truthy?(value)
        return false if value.nil?

        %w[1 true yes on].include?(value.to_s.strip.downcase)
      end
      private_class_method :truthy?
    end
  end
end
