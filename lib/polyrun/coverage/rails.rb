require "yaml"

require_relative "collector"
require_relative "formatter"

module Polyrun
  module Coverage
    # Rails integration entry point for {Collector.start!}: optional +config/polyrun_coverage.yml+ under the project
    # root, root inference from +spec_helper.rb+ / +rails_helper.rb+ / +test_helper.rb+, and +report_formats+ for
    # {Formatter.multi}. Call at the **top** of +spec/spec_helper.rb+ (before +require "rails"+) so stdlib
    # +Coverage+ sees application code.
    #
    #   require "polyrun/coverage/rails"
    #   Polyrun::Coverage::Rails.start!
    #
    module Rails
      module_function

      DEFAULT_CONFIG_RELATIVE = File.join("config", "polyrun_coverage.yml").freeze

      # @param root [String, nil] project root (default: infer from caller, or +Rails.root+ when already loaded)
      # @param config_path [String, nil] YAML path (default: +<root>/config/polyrun_coverage.yml+ if present)
      # @param overrides [Hash] merged over YAML; keys match {Collector.start!} (+report_formats+ builds +formatter+)
      def start!(root: nil, config_path: nil, **overrides)
        return if Collector.disabled?

        root = resolve_root(root)
        root = File.expand_path(root)
        cfg = load_config(root, config_path)
        merged = deep_merge_hashes(cfg, stringify_keys(overrides))
        merged["root"] = root

        report_formats = merged.delete("report_formats")
        unless merged.key?("formatter") || report_formats.nil?
          merged["formatter"] = build_formatter(Array(report_formats), root, merged)
        end

        Collector.start!(**collector_kwargs(merged))
      end

      # Exposed for tests and custom loaders.
      def infer_root_from_path(path)
        case File.basename(path.to_s)
        when "spec_helper.rb", "rails_helper.rb", "test_helper.rb"
          File.expand_path("..", File.dirname(path))
        end
      end

      def resolve_root(explicit)
        return File.expand_path(explicit) if explicit

        if defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root
          return ::Rails.root.to_s
        end

        caller_locations.each do |loc|
          inferred = infer_root_from_path(loc.path)
          return inferred if inferred
        end

        raise ArgumentError,
          "Polyrun::Coverage::Rails.start! could not infer project root; pass root: (e.g. Rails.root or File.expand_path('..', __dir__))"
      end

      def load_config(root, config_path)
        path = config_path || File.join(root, DEFAULT_CONFIG_RELATIVE)
        path = File.expand_path(path)
        return {} unless File.file?(path)

        data = YAML.load_file(path)
        data.is_a?(Hash) ? stringify_keys(data) : {}
      end

      def build_formatter(formats, root, merged)
        return nil if formats.empty?

        dir = merged["report_output_dir"] || File.join(root, "coverage")
        dir = File.expand_path(dir.to_s, root)
        base = (merged["report_basename"] || "polyrun-coverage").to_s
        Formatter.multi(*formats.map { |x| x.to_s.to_sym }, output_dir: dir, basename: base)
      end

      def collector_kwargs(h)
        root = File.expand_path(h.fetch("root"))
        {
          root: root,
          reject_patterns: Array(h["reject_patterns"] || []),
          track_under: h.key?("track_under") ? Array(h["track_under"]) : ["lib"],
          track_files: h["track_files"],
          groups: h["groups"],
          output_path: h["output_path"],
          minimum_line_percent: h["minimum_line_percent"],
          strict: h["strict"],
          meta: h["meta"].is_a?(Hash) ? h["meta"] : {},
          formatter: h["formatter"],
          report_output_dir: (h["report_output_dir"] ? File.expand_path(h["report_output_dir"].to_s, root) : nil),
          report_basename: (h["report_basename"] || "polyrun-coverage").to_s
        }
      end

      def stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), out|
            out[k.to_s] = stringify_keys(v)
          end
        when Array
          obj.map { |e| stringify_keys(e) }
        else
          obj
        end
      end

      def deep_merge_hashes(a, b)
        a = a.is_a?(Hash) ? a.dup : {}
        b.each do |k, v|
          key = k.to_s
          a[key] = if a[key].is_a?(Hash) && v.is_a?(Hash)
            deep_merge_hashes(a[key], stringify_keys(v))
          else
            stringify_keys(v)
          end
        end
        a
      end
    end
  end
end
