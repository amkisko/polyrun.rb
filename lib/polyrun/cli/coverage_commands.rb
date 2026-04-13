require "json"
require "fileutils"
require "optparse"

require_relative "coverage_merge_io"

module Polyrun
  class CLI
    module CoverageCommands
      include CoverageMergeIo

      private

      def cmd_merge_coverage(argv, _config_path)
        inputs, output, formats = merge_coverage_parse_argv(argv)
        if inputs.empty?
          Polyrun::Log.warn "merge-coverage: need at least one existing -i FILE (after glob expansion)"
          return 2
        end

        Polyrun::Log.warn "merge-coverage: merging #{inputs.size} fragment(s)" if @verbose
        Polyrun::Debug.log_kv(
          merge_coverage: "start",
          output: output,
          formats: formats,
          input_paths: inputs
        )
        input_bytes = inputs.sum { |p| File.size(p) }
        Polyrun::Debug.log("merge-coverage: input_bytes=#{input_bytes}")

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        r = merge_coverage_merge_fragments(inputs)
        merged = r[:blob]
        Polyrun::Debug.log("merge-coverage: merged_blob file_count=#{merged.size}")

        payload = Polyrun::Coverage::Merge.to_simplecov_json(merged, meta: r[:meta], groups: r[:groups])
        out_abs = File.expand_path(output)
        merge_coverage_write_json_payload(out_abs, payload)
        merge_coverage_write_format_outputs(merged, r, out_abs, formats)

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        merge_coverage_log_finish(elapsed, inputs)
        0
      end

      # Warn when wall time exceeds this many seconds (default 10). Set POLYRUN_MERGE_SLOW_WARN_SECONDS=0 to disable.
      def merge_slow_warn_threshold_seconds
        v = ENV["POLYRUN_MERGE_SLOW_WARN_SECONDS"]
        return 10.0 if v.nil? || v.to_s.strip.empty?

        s = v.to_s.strip.downcase
        return nil if %w[0 false no].include?(s)

        Float(v)
      rescue ArgumentError
        10.0
      end

      def cmd_report_coverage(argv)
        input = nil
        output_dir = "coverage/polyrun"
        basename = "polyrun-coverage"
        formats = Polyrun::Coverage::Reporting::DEFAULT_FORMATS.dup

        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-coverage -i FILE [-o DIR] [--basename NAME] [--format json,lcov,cobertura,console,html]"
          opts.on("-i", "--input PATH", "Merged or raw SimpleCov JSON") { |v| input = v }
          opts.on("-o", "--output DIR", "Output directory") { |v| output_dir = v }
          opts.on("--basename NAME", "File name prefix") { |v| basename = v }
          opts.on("--format LIST", String) { |v| formats = v.split(",").map(&:strip) }
        end
        parser.parse!(argv)
        input ||= argv.first

        unless input && File.file?(input)
          Polyrun::Log.warn "report-coverage: need -i FILE or a path argument"
          return 2
        end

        paths = Polyrun::Debug.time("report-coverage: write_from_json_file") do
          Polyrun::Coverage::Reporting.write_from_json_file(
            File.expand_path(input),
            output_dir: File.expand_path(output_dir),
            basename: basename,
            formats: formats
          )
        end
        Polyrun::Log.puts JSON.generate(paths.transform_keys(&:to_s))
        0
      end

      def merge_coverage_after_shards(output:, format_list:, config_path:)
        files = merge_coverage_fragment_json_files
        if files.empty?
          Polyrun::Log.warn "polyrun run-shards: --merge-coverage: no coverage/polyrun-fragment-*.json found (enable Polyrun coverage in spec_helper?)"
          return 0
        end

        merge_coverage_after_shards_log_start(files, output, format_list)
        code = merge_coverage_after_shards_run_merge(files, output, format_list, config_path)
        return code unless code == 0

        merge_coverage_after_shards_strict_gate(output, code)
      rescue JSON::ParserError => e
        Polyrun::Log.warn "polyrun run-shards: merged coverage JSON parse failed: #{e.message}"
        1
      end

      def merge_coverage_fragment_json_files
        pattern = File.join(Dir.pwd, "coverage", "polyrun-fragment-*.json")
        Dir.glob(pattern).sort
      end

      def merge_coverage_after_shards_log_start(files, output, format_list)
        Polyrun::Log.warn "polyrun run-shards: merging #{files.size} coverage fragment(s) → #{output}"
        Polyrun::Debug.log("merge-coverage-after-shards: #{files.size} fragment(s) → #{output} format=#{format_list}")
        Polyrun::Debug.log("merge-coverage-after-shards: fragments=#{files.join(", ")}")
      end

      def merge_coverage_after_shards_run_merge(files, output, format_list, config_path)
        merge_argv = []
        files.each { |f| merge_argv.push("-i", f) }
        merge_argv += ["-o", output, "--format", format_list]
        Polyrun::Debug.time("merge-coverage (parent after workers)") do
          cmd_merge_coverage(merge_argv, config_path)
        end
      end

      def merge_coverage_after_shards_strict_gate(output, code)
        gate = coverage_minimum_line_gate_from_polyrun_coverage_yml
        Polyrun::Debug.log_kv(
          coverage_gate_config: "polyrun_coverage.yml",
          gate: gate.inspect
        )
        return code if gate.nil? || !gate[:strict]

        merged_path = File.expand_path(output)
        unless File.file?(merged_path)
          Polyrun::Log.warn "polyrun run-shards: --merge-coverage: expected merged JSON at #{merged_path} missing"
          return 1
        end

        below = merge_coverage_min_line_gate_below?(merged_path, gate)
        return 1 if below

        code
      end
    end
  end
end
