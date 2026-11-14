require_relative "tool_validation"

module Polyrun
  class Config
    module Tools
      module_function

      def merge(base, overlay)
        base.merge(overlay) { |_, before, after| (before.is_a?(Hash) && after.is_a?(Hash)) ? merge(before, after) : after }
      end

      def runtime(feature, settings = {})
        raise ArgumentError, "settings must be a mapping" unless settings.is_a?(Hash)

        value = merge(ToolDefaults.for(feature), stringify(settings))
        errors = ToolValidation.check(value, ToolDefaults.for(feature), feature.to_s)
        raise ArgumentError, errors.join("; ") unless errors.empty?

        value
      end

      def resolve(cfg, feature, overrides: {}, env: ENV, root: Dir.pwd)
        errors = validate(cfg.raw)
        raise ArgumentError, errors.join("; ") unless errors.empty?

        raw = stringify(cfg.raw)
        defaults = ToolDefaults.for(feature)
        shared = shared_defaults(raw).slice(*defaults.keys)
        value = merge(merge(defaults, shared), feature_config(raw, feature))
        value = merge(value, environment(feature, env))
        value = runtime(feature, merge(value, stringify(overrides)))
        normalize_paths(value, root)
      end

      def shared_defaults(raw)
        shared = raw.slice(*ToolDefaults::SHARED.keys)
        if shared["workers"].is_a?(String)
          shared["workers"] = Integer(shared["workers"], exception: false) || shared["workers"]
        end
        shared
      end

      def normalize_paths(value, root)
        value["root"] = File.expand_path(value["root"] || root, root)
        %w[output subjects_file].each { |key| value[key] = File.expand_path(value[key], value["root"]) if value[key] }
        value
      end

      def feature_config(raw, feature)
        return raw.fetch(feature, {}) unless %w[observe measure].include?(feature)

        quality = raw.fetch("quality", {})
        merge(quality.slice(*ToolDefaults.for(feature).keys), quality.fetch(feature, {}))
      end

      def environment(feature, env)
        result = {}
        applicable = ToolDefaults.for(feature)
        {"workers" => "POLYRUN_WORKERS", "timeout" => "POLYRUN_TIMEOUT", "max_output_bytes" => "POLYRUN_MAX_OUTPUT_BYTES"}.each do |key, name|
          next if !applicable.key?(key) || env[name].nil? || env[name].empty?

          result[key] = (key == "timeout") ? Float(env[name]) : Integer(env[name])
        end
        name = "POLYRUN_#{%w[observe measure].include?(feature) ? "QUALITY" : feature.upcase}"
        if env.key?(name)
          raise ArgumentError, "invalid #{name}" unless %w[1 true yes on 0 false no off].include?(env[name].downcase)

          result["enabled"] = %w[1 true yes on].include?(env[name].downcase)
        end
        result
      end

      def validate(raw)
        raw = stringify(raw)
        errors = ToolValidation.check(shared_defaults(raw), ToolDefaults::SHARED, "config")
        errors << 'unknown top-level key "global"' if raw.key?("global")
        %w[graph mutation].each do |feature|
          errors.concat(ToolValidation.check(raw[feature], ToolDefaults.for(feature), feature)) if raw.key?(feature)
        end
        errors.concat(validate_quality(raw["quality"])) if raw.key?("quality")
        errors
      end

      def validate_quality(quality)
        return ["quality must be a mapping"] unless quality.is_a?(Hash)

        errors = ToolValidation.check(quality.except("observe", "measure", "spec_quality"), ToolDefaults::COMMON.slice(*ToolDefaults::EXECUTION, "max_artifact_bytes"), "quality")
        %w[observe measure].each do |feature|
          errors.concat(ToolValidation.check(quality[feature], ToolDefaults.for(feature), "quality.#{feature}")) if quality.key?(feature)
        end
        if quality.key?("spec_quality")
          require_relative "../spec_quality/config"
          defaults = SpecQuality::Config::DEFAULTS.merge("enabled" => false)
          errors.concat(ToolValidation.check(quality["spec_quality"], defaults, "quality.spec_quality"))
        end
        errors
      end

      def spec_quality(root:, env: ENV)
        cfg = Config.load(path: env["POLYRUN_CONFIG"], root: root, suite: env["POLYRUN_SUITE"])
        errors = validate(cfg.raw)
        raise ArgumentError, errors.join("; ") unless errors.empty?

        raw = stringify(cfg.raw)
        shared = shared_defaults(raw)
        settings = {}
        settings["track_under"] = shared["source_roots"] if shared.key?("source_roots")
        merge(settings, raw.fetch("quality", {}).fetch("spec_quality", {}))
      end

      def stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { |item| stringify(item) }
        else value
        end
      end
    end
  end
end
