require "json"
require "fileutils"
require "optparse"

module Polyrun
  class CLI
    module CoverageCommands
      private

      def cmd_merge_coverage(argv, _config_path)
        inputs = []
        output = "coverage/polyrun-merged.json"
        formats = ["json"]

        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun merge-coverage -i FILE [-i FILE] [-o PATH] [--format json,lcov,cobertura,console,html]"
          opts.on("-i", "--input FILE", "Coverage JSON (repeatable; globs ok)") do |f|
            expand_merge_input_pattern(f).each { |x| inputs << x }
          end
          opts.on("-o", "--output PATH", String) { |v| output = v }
          opts.on("--format LIST", String) { |v| formats = v.split(",").map(&:strip) }
        end
        parser.parse!(argv)

        inputs.uniq!
        inputs.select! { |p| File.file?(p) }
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
        r = Polyrun::Debug.time("Coverage::Merge.merge_fragments") do
          Polyrun::Coverage::Merge.merge_fragments(inputs)
        end
        merged = r[:blob]
        Polyrun::Debug.log("merge-coverage: merged_blob file_count=#{merged.size}")

        payload = Polyrun::Coverage::Merge.to_simplecov_json(merged, meta: r[:meta], groups: r[:groups])

        out_abs = File.expand_path(output)
        Polyrun::Debug.time("write merged JSON") do
          FileUtils.mkdir_p(File.dirname(out_abs))
          File.write(out_abs, JSON.generate(payload))
        end

        if formats.include?("lcov")
          lcov_path = out_abs.sub(/\.json\z/, ".lcov")
          lcov_path = "#{out_abs}.lcov" if lcov_path == out_abs
          Polyrun::Debug.time("write lcov") { File.write(lcov_path, Polyrun::Coverage::Merge.emit_lcov(merged)) }
        end

        if formats.include?("cobertura")
          cob_path = out_abs.sub(/\.json\z/, ".xml")
          cob_path = "#{out_abs}.cobertura.xml" if cob_path == out_abs
          root = nil
          if r[:meta].is_a?(Hash)
            root = r[:meta]["polyrun_coverage_root"] || r[:meta][:polyrun_coverage_root]
          end
          Polyrun::Debug.time("write cobertura XML") do
            File.write(cob_path, Polyrun::Coverage::Merge.emit_cobertura(merged, root: root))
          end
        end

        if formats.include?("console")
          sum_path = out_abs.sub(/\.json\z/, "-summary.txt")
          sum_path = "#{out_abs}-summary.txt" if sum_path == out_abs
          summary = Polyrun::Coverage::Merge.console_summary(merged)
          summary_text = Polyrun::Coverage::Merge.format_console_summary(summary)
          Polyrun::Debug.time("write console summary") { File.write(sum_path, summary_text) }
          Polyrun::Log.print summary_text
        end

        if formats.include?("html")
          html_path = out_abs.sub(/\.json\z/, ".html")
          html_path = "#{out_abs}.html" if html_path == out_abs
          Polyrun::Debug.time("write HTML report") { File.write(html_path, Polyrun::Coverage::Merge.emit_html(merged)) }
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        if (thr = merge_slow_warn_threshold_seconds) && elapsed > thr
          Polyrun::Log.warn format(
            "merge-coverage: slow merge took %.2fs (warn above %.0fs; typical suites are JSON fragments, not TB-scale data; disable: POLYRUN_MERGE_SLOW_WARN_SECONDS=0)",
            elapsed,
            thr
          )
        end

        if @verbose || ENV["POLYRUN_PROFILE_MERGE"] == "1" || Polyrun::Debug.enabled?
          Polyrun::Log.warn format("merge-coverage: finished in %.2fs (%d input fragment(s))", elapsed, inputs.size)
        end

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
        pattern = File.join(Dir.pwd, "coverage", "polyrun-fragment-*.json")
        files = Dir.glob(pattern).sort
        if files.empty?
          Polyrun::Log.warn "polyrun run-shards: --merge-coverage: no coverage/polyrun-fragment-*.json found (enable Polyrun coverage in spec_helper?)"
          return 0
        end

        Polyrun::Log.warn "polyrun run-shards: merging #{files.size} coverage fragment(s) → #{output}"
        Polyrun::Debug.log("merge-coverage-after-shards: #{files.size} fragment(s) → #{output} format=#{format_list}")
        Polyrun::Debug.log("merge-coverage-after-shards: fragments=#{files.join(", ")}")

        merge_argv = []
        files.each { |f| merge_argv.push("-i", f) }
        merge_argv += ["-o", output, "--format", format_list]
        code = Polyrun::Debug.time("merge-coverage (parent after workers)") do
          cmd_merge_coverage(merge_argv, config_path)
        end
        return code unless code == 0

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

        below = false
        Polyrun::Debug.time("minimum_line_percent gate (merged JSON)") do
          data = JSON.parse(File.read(merged_path))
          blob = Polyrun::Coverage::Merge.extract_coverage_blob(data)
          summary = Polyrun::Coverage::Merge.console_summary(blob)
          min = gate[:minimum]
          below = summary[:line_percent].round < min.round
          Polyrun::Debug.log_kv(
            merged_line_percent: summary[:line_percent],
            gate_minimum: min,
            below_gate: below
          )
          if below
            Polyrun::Log.warn Polyrun::Coverage::Merge.format_console_summary(summary)
            Polyrun::Log.warn "Polyrun coverage: #{summary[:line_percent].round(2)}% rounds below minimum #{min}% (merged)."
          end
        end
        return 1 if below

        code
      rescue JSON::ParserError => e
        Polyrun::Log.warn "polyrun run-shards: merged coverage JSON parse failed: #{e.message}"
        1
      end
    end
  end
end
