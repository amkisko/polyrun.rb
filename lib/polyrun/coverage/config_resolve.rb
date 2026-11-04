require "yaml"
require_relative "../config/suite"

module Polyrun
  module Coverage
    # Resolves coverage settings for {Rails.start!} and CLI gates.
    #
    # Order: explicit +config_path+ when that file exists; else +config/polyrun_coverage.yml+
    # when present; else inline +coverage:+ from +polyrun.yml+ (or +POLYRUN_CONFIG+).
    # Aliases: +formats+ -> +report_formats+; directory-like +output_path+ -> +report_output_dir+.
    module ConfigResolve
      module_function

      DEFAULT_FILE = File.join("config", "polyrun_coverage.yml").freeze
      POLYRUN_YML_NAMES = %w[polyrun.yml config/polyrun.yml].freeze
      META_KEYS = %w[coverage_config_source].freeze

      def load(root:, config_path: nil, polyrun_config_path: nil)
        root = File.expand_path(root)
        file_path, file_hash = load_file_coverage(root, config_path)
        if file_path
          chosen = file_hash
          source = relative_or_basename(file_path)
        else
          inline_path = resolve_polyrun_yml(root, polyrun_config_path)
          chosen = load_inline_coverage(inline_path)
          source = chosen.empty? ? "none" : relative_or_basename(inline_path)
        end
        normalize_aliases!(chosen, root)
        chosen["coverage_config_source"] = source
        chosen
      end

      def minimum_line_gate(root: Dir.pwd, config_path: nil, polyrun_config_path: nil)
        data = load(root: root, config_path: config_path, polyrun_config_path: polyrun_config_path)
        min = data["minimum_line_percent"]
        return nil if min.nil?

        strict = data.key?("strict") ? data["strict"] != false : true
        {minimum: min.to_f, strict: strict}
      end

      def load_inline_coverage(path)
        return {} unless path

        raw = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
        return {} unless raw.is_a?(Hash)

        raw, = Polyrun::Config::Suite.merge(raw, ENV["POLYRUN_SUITE"])
        cov = raw["coverage"] || raw[:coverage]
        cov.is_a?(Hash) ? stringify_keys(cov) : {}
      rescue Psych::SyntaxError, ArgumentError, TypeError
        {}
      end
      private_class_method :load_inline_coverage

      def load_file_coverage(root, config_path)
        path =
          if config_path && !config_path.to_s.strip.empty?
            File.expand_path(config_path.to_s)
          else
            File.join(root, DEFAULT_FILE)
          end
        return [nil, {}] unless File.file?(path)

        data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
        hash = data.is_a?(Hash) ? stringify_keys(data) : {}
        [path, hash]
      rescue Psych::SyntaxError, ArgumentError, TypeError
        [path, {}]
      end
      private_class_method :load_file_coverage

      def resolve_polyrun_yml(root, explicit)
        if explicit && !explicit.to_s.strip.empty?
          p = File.expand_path(explicit.to_s)
          return p if File.file?(p)

          return nil
        end

        env = ENV["POLYRUN_CONFIG"]
        if env && !env.empty?
          p = File.expand_path(env)
          return p if File.file?(p)
        end

        POLYRUN_YML_NAMES.each do |name|
          full = File.expand_path(name, root)
          return full if File.file?(full)
        end
        nil
      end
      private_class_method :resolve_polyrun_yml

      def normalize_aliases!(h, root)
        if !h.key?("report_formats") && h.key?("formats")
          h["report_formats"] = Array(h.delete("formats"))
        end
        return if h.key?("report_output_dir")
        return unless h.key?("output_path")

        out = h["output_path"].to_s
        return if out.empty? || out.end_with?(".json")

        h["report_output_dir"] = File.expand_path(out, root)
        h.delete("output_path")
      end
      private_class_method :normalize_aliases!

      def relative_or_basename(path)
        return DEFAULT_FILE if path.end_with?(DEFAULT_FILE)

        File.basename(path)
      end
      private_class_method :relative_or_basename

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
      private_class_method :stringify_keys
    end
  end
end
