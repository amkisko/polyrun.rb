require "fileutils"
require "json"

module Polyrun
  module Coverage
    module Collector
      module_function

      def finish
        cfg = @config || return # rubocop:disable ThreadSafety/ClassInstanceVariable -- Collector stores @config from start! (same process)
        Polyrun::Debug.log_worker_kv(
          collector_finish: "start",
          polyrun_shard_index: ENV["POLYRUN_SHARD_INDEX"],
          polyrun_shard_total: ENV["POLYRUN_SHARD_TOTAL"],
          polyrun_shard_matrix_index: ENV["POLYRUN_SHARD_MATRIX_INDEX"],
          polyrun_shard_matrix_total: ENV["POLYRUN_SHARD_MATRIX_TOTAL"],
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

      def self.prepare_finish_blob(cfg)
        raw = ::Coverage.result
        blob = Collector.result_to_blob(raw)
        blob = Collector.normalize_blob_paths(blob, cfg[:root])
        blob = Collector.send(:track_blob_for_finish, cfg, blob)
        Filter.reject_matching_paths(blob, cfg[:reject_patterns])
      end
      private_class_method :prepare_finish_blob

      def self.track_blob_for_finish(cfg, blob)
        sharded = ENV["POLYRUN_SHARD_TOTAL"].to_i > 1
        if cfg[:track_files]
          filtered = TrackFiles.keep_tracked_files(blob, cfg[:root], cfg[:track_files])
          return filtered if sharded

          TrackFiles.merge_untracked_into_blob(filtered, cfg[:root], cfg[:track_files])
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

      def self.exit_if_below_minimum_line_percent(cfg, summary)
        shard_total = (cfg[:shard_total_at_start] || ENV["POLYRUN_SHARD_TOTAL"]).to_i
        return unless cfg[:minimum_line_percent] && shard_total <= 1

        min = cfg[:minimum_line_percent].to_f
        return if summary[:line_percent].round >= min.round

        Polyrun::Log.warn Merge.format_console_summary(summary)
        Polyrun::Log.warn "Polyrun coverage: #{summary[:line_percent].round(2)}% rounds below minimum #{min}%."
        exit 1 if cfg[:strict]
      end
      private_class_method :exit_if_below_minimum_line_percent
    end
  end
end
