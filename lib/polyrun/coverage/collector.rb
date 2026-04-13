require "coverage"
require "fileutils"
require "json"

require_relative "cobertura_zero_lines"
require_relative "filter"
require_relative "formatter"
require_relative "merge"
require_relative "result"
require_relative "track_files"
require_relative "../debug"

module Polyrun
  module Coverage
    # Stdlib +Coverage+ → SimpleCov-compatible JSON for +merge-coverage+ / +report-coverage+.
    # No SimpleCov gem. Enable with +POLYRUN_COVERAGE=1+ or call +start!+ from spec_helper.
    #
    # Disable with +POLYRUN_COVERAGE_DISABLE=1+ or +SIMPLECOV_DISABLE=1+ (migration alias).
    #
    # Branch coverage: set +POLYRUN_COVERAGE_BRANCHES=1+ so stdlib +Coverage.start+ records branches;
    # +merge-coverage+ merges branch keys when present in fragments.
    module Collector
      module_function

      # @param root [String] project root (absolute or relative)
      # @param reject_patterns [Array<String>] path substrings to drop (like SimpleCov add_filter)
      # @param output_path [String, nil] default coverage/polyrun-fragment-<shard>.json
      # @param minimum_line_percent [Float, nil] exit 1 if below (when strict)
      # @param strict [Boolean] whether to exit non-zero on threshold failure (default true when minimum set)
      # @param track_under [Array<String>] when +track_files+ is nil, only keep coverage keys under these dirs relative to +root+. Default +["lib"]+.
      # @param track_files [String, Array<String>, nil] glob(s) relative to +root+ (e.g. +"{lib,app}/**/*.rb"+). Adds never-loaded files with simulated lines, like SimpleCov +track_files+.
      # @param groups [Hash{String=>String}] group name => glob relative to +root+ (SimpleCov +add_group+); JSON gets +lines.covered_percent+ per group and optional "Ungrouped".
      # @param meta [Hash] extra keys under merged JSON meta
      # @param formatter [Object, nil] Object responding to +format(result, output_dir:, basename:)+ like SimpleCov formatters (e.g. {Formatter.multi} or {Formatter::MultiFormatter})
      # @param report_output_dir [String, nil] directory for +formatter+ outputs (default +coverage/+ under +root+)
      # @param report_basename [String] file prefix for formatter outputs (default +polyrun-coverage+)
      def start!(root:, reject_patterns: [], track_under: ["lib"], track_files: nil, groups: nil, output_path: nil, minimum_line_percent: nil, strict: nil, meta: {}, formatter: nil, report_output_dir: nil, report_basename: "polyrun-coverage")
        return if disabled?

        root = File.expand_path(root)
        shard = ENV.fetch("POLYRUN_SHARD_INDEX", "0")
        output_path ||= File.join(root, "coverage", "polyrun-fragment-#{shard}.json")
        strict = if minimum_line_percent.nil?
          false
        else
          strict.nil? || strict
        end

        @config = {
          root: root,
          track_under: Array(track_under).map(&:to_s),
          track_files: track_files,
          groups: normalize_groups(groups),
          reject_patterns: reject_patterns,
          output_path: output_path,
          minimum_line_percent: minimum_line_percent,
          strict: strict,
          meta: meta,
          formatter: formatter,
          report_output_dir: report_output_dir,
          report_basename: report_basename
        }

        ::Coverage.start(lines: true, branches: branch_coverage_enabled?)
        at_exit { finish }
        nil
      end

      def branch_coverage_enabled?
        %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_BRANCHES"]&.downcase)
      end

      def disabled?
        %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_DISABLE"]&.downcase) ||
          %w[1 true yes].include?(ENV["SIMPLECOV_DISABLE"]&.downcase)
      end

      # True after a successful {start!} in this process (stdlib +Coverage+ is active).
      def self.started?
        instance_variable_defined?(:@config) && @config
      end

      # Whether +polyrun quick+ should call {Rails.start!} before loading quick files: not disabled,
      # and (+POLYRUN_COVERAGE=1+ or +config/polyrun_coverage.yml+ exists under +root+).
      def self.coverage_requested_for_quick?(root = Dir.pwd)
        return false if disabled?
        return true if %w[1 true yes].include?(ENV["POLYRUN_COVERAGE"]&.to_s&.downcase)

        File.file?(File.join(File.expand_path(root), "config", "polyrun_coverage.yml"))
      end

      # When +POLYRUN_SHARD_TOTAL+ > 1, each worker only writes the JSON fragment; merged reports
      # (+merge-coverage+ / +report-coverage+) are authoritative. Set +POLYRUN_COVERAGE_WORKER_FORMATS=1+
      # to force per-worker formatter output (debug only; duplicates work N times).
      def run_formatter_per_worker?
        return true if ENV["POLYRUN_COVERAGE_WORKER_FORMATS"] == "1"

        ENV["POLYRUN_SHARD_TOTAL"].to_i <= 1
      end

      def self.finish_debug_time_label
        if ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
          "worker pid=#{$$} shard=#{ENV.fetch("POLYRUN_SHARD_INDEX", "?")} Coverage::Collector.finish (write fragment)"
        else
          "Coverage::Collector.finish (write fragment)"
        end
      end

      def finish
        cfg = @config || return
        Polyrun::Debug.log_worker_kv(
          collector_finish: "start",
          polyrun_shard_index: ENV["POLYRUN_SHARD_INDEX"],
          polyrun_shard_total: ENV["POLYRUN_SHARD_TOTAL"],
          output_path: cfg[:output_path]
        )
        Polyrun::Debug.time(Collector.finish_debug_time_label) do
          blob = Collector.send(:prepare_finish_blob, cfg)
          summary = Merge.console_summary(blob)
          group_payload = cfg[:groups] ? TrackFiles.group_summaries(blob, cfg[:root], cfg[:groups]) : nil

          Collector.send(:exit_if_below_minimum_line_percent, cfg, summary)

          Collector.send(:write_finish_fragment!, cfg, blob, group_payload)
          Collector.send(:run_finish_formatter!, cfg, blob, group_payload)
          Polyrun::Log.warn Merge.format_console_summary(summary) if ENV["POLYRUN_COVERAGE_VERBOSE"]
        end
      end

      def build_meta(cfg)
        m = (cfg[:meta] || {}).transform_keys(&:to_s)
        m["polyrun_version"] = Polyrun::VERSION
        m["timestamp"] ||= Time.now.to_i
        m["command_name"] ||= "rspec"
        m["polyrun_coverage_root"] = cfg[:root].to_s
        if cfg[:groups]
          m["polyrun_coverage_groups"] = cfg[:groups].transform_keys(&:to_s).transform_values(&:to_s)
        end
        if cfg[:track_files]
          m["polyrun_track_files"] = cfg[:track_files]
        end
        m
      end

      # Normalizes stdlib Coverage.result to merge-compatible file entries (lines; branches when collected).
      def result_to_blob(raw)
        out = {}
        raw.each do |path, cov|
          next unless cov.is_a?(Hash)

          lines = cov[:lines] || cov["lines"]
          next unless lines.is_a?(Array)

          entry = {"lines" => lines.map { |x| x }}
          br = cov[:branches] || cov["branches"]
          entry["branches"] = br if br
          out[path.to_s] = entry
        end
        out
      end

      def normalize_blob_paths(blob, root)
        root = File.expand_path(root)
        blob.each_with_object({}) do |(path, entry), acc|
          acc[File.expand_path(path.to_s, root)] = entry
        end
      end

      def normalize_groups(groups)
        return nil if groups.nil?

        h = groups.is_a?(Hash) ? groups : {}
        return nil if h.empty?

        h.transform_keys(&:to_s).transform_values(&:to_s)
      end

      def keep_under_root(blob, root, track_under)
        return blob if track_under.nil? || track_under.empty?

        root = File.expand_path(root)
        prefixes = track_under.map { |d| File.join(root, d) }
        blob.each_with_object({}) do |(path, entry), acc|
          p = path.to_s
          next unless prefixes.any? { |pre| p == pre || p.start_with?(pre + "/") }

          acc[path] = entry
        end
      end

      # Private singletons: +module_function+ +finish+ cannot call private instance helpers defined below
      # +finish+ in the same module (Ruby lookup); use +send+ to these from +finish+.
      def self.prepare_finish_blob(cfg)
        raw = ::Coverage.result
        blob = Collector.result_to_blob(raw)
        blob = Collector.normalize_blob_paths(blob, cfg[:root])
        blob = Collector.send(:track_blob_for_finish, cfg, blob)
        Filter.reject_matching_paths(blob, cfg[:reject_patterns])
      end
      private_class_method :prepare_finish_blob

      # Per-shard untracked expansion is applied once in Merge.merge_fragments when sharded so merged
      # denominators match a single serial run (avoids inflated lines_relevant).
      def self.track_blob_for_finish(cfg, blob)
        sharded = ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
        if cfg[:track_files]
          return Collector.keep_under_root(blob, cfg[:root], cfg[:track_under]) if sharded

          TrackFiles.merge_untracked_into_blob(blob, cfg[:root], cfg[:track_files])
        else
          Collector.keep_under_root(blob, cfg[:root], cfg[:track_under])
        end
      end
      private_class_method :track_blob_for_finish

      def self.write_finish_fragment!(cfg, blob, group_payload)
        FileUtils.mkdir_p(File.dirname(cfg[:output_path]))
        payload = Merge.to_simplecov_json(blob, meta: Collector.build_meta(cfg), groups: group_payload)
        File.write(cfg[:output_path], JSON.generate(payload))
        Polyrun::Debug.log_worker("Collector.finish: wrote #{cfg[:output_path]} bytes=#{File.size(cfg[:output_path])}")
      end
      private_class_method :write_finish_fragment!

      def self.run_finish_formatter!(cfg, blob, group_payload)
        return unless cfg[:formatter]

        if Collector.run_formatter_per_worker?
          dir = cfg[:report_output_dir] || File.join(cfg[:root], "coverage")
          base = cfg[:report_basename] || "polyrun-coverage"
          result = Result.new(blob, meta: Collector.build_meta(cfg), groups: group_payload)
          Polyrun::Debug.time("Collector formatter (per-shard reports)") do
            cfg[:formatter].format(result, output_dir: dir, basename: base)
            xml_path = File.join(dir, "#{base}.xml")
            CoberturaZeroLines.run(xml_path: xml_path, filename_prefix: "lib/") if File.file?(xml_path)
          end
        else
          shard_total = ENV.fetch("POLYRUN_SHARD_TOTAL", "nil")
          Polyrun::Debug.log_worker(
            "Collector.finish: skipping per-worker formatter (POLYRUN_SHARD_TOTAL=#{shard_total}); " \
            "use merge-coverage / report-coverage for full LCOV/Cobertura/HTML"
          )
        end
      end
      private_class_method :run_finish_formatter!

      # Per-worker blobs are incomplete when POLYRUN_SHARD_TOTAL > 1; parallel-rspec merge applies the gate.
      def self.exit_if_below_minimum_line_percent(cfg, summary)
        return unless cfg[:minimum_line_percent] && ENV["POLYRUN_SHARD_TOTAL"].to_i <= 1

        min = cfg[:minimum_line_percent].to_f
        # Integer rounding matches how teams read coverage gates (e.g. 89.89% → pass 90% floor).
        return if summary[:line_percent].round >= min.round

        Polyrun::Log.warn Merge.format_console_summary(summary)
        Polyrun::Log.warn "Polyrun coverage: #{summary[:line_percent].round(2)}% rounds below minimum #{min}%."
        exit 1 if cfg[:strict]
      end
      private_class_method :exit_if_below_minimum_line_percent
    end
  end
end
