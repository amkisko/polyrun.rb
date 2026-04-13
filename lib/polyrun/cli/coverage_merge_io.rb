require "json"
require "fileutils"
require "optparse"

module Polyrun
  class CLI
    # Writes merged coverage blob to requested formats (merge-coverage / run-shards).
    module CoverageMergeIo
      private

      def merge_coverage_parse_argv(argv)
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
        [inputs, output, formats]
      end

      def merge_coverage_merge_fragments(inputs)
        Polyrun::Debug.time("Coverage::Merge.merge_fragments") do
          Polyrun::Coverage::Merge.merge_fragments(inputs)
        end
      end

      def merge_coverage_write_json_payload(out_abs, payload)
        Polyrun::Debug.time("write merged JSON") do
          FileUtils.mkdir_p(File.dirname(out_abs))
          File.write(out_abs, JSON.generate(payload))
        end
      end

      def merge_coverage_write_format_outputs(merged, r, out_abs, formats)
        write_merge_lcov(merged, out_abs) if formats.include?("lcov")
        write_merge_cobertura(merged, r, out_abs) if formats.include?("cobertura")
        write_merge_console(merged, out_abs) if formats.include?("console")
        write_merge_html(merged, out_abs) if formats.include?("html")
      end

      def write_merge_lcov(merged, out_abs)
        lcov_path = out_abs.sub(/\.json\z/, ".lcov")
        lcov_path = "#{out_abs}.lcov" if lcov_path == out_abs
        Polyrun::Debug.time("write lcov") { File.write(lcov_path, Polyrun::Coverage::Merge.emit_lcov(merged)) }
      end

      def write_merge_cobertura(merged, r, out_abs)
        cob_path = out_abs.sub(/\.json\z/, ".xml")
        cob_path = "#{out_abs}.cobertura.xml" if cob_path == out_abs
        root = merge_cobertura_root(r)
        Polyrun::Debug.time("write cobertura XML") do
          File.write(cob_path, Polyrun::Coverage::Merge.emit_cobertura(merged, root: root))
        end
      end

      def merge_cobertura_root(r)
        return nil unless r[:meta].is_a?(Hash)

        r[:meta]["polyrun_coverage_root"] || r[:meta][:polyrun_coverage_root]
      end

      def write_merge_console(merged, out_abs)
        sum_path = out_abs.sub(/\.json\z/, "-summary.txt")
        sum_path = "#{out_abs}-summary.txt" if sum_path == out_abs
        summary = Polyrun::Coverage::Merge.console_summary(merged)
        summary_text = Polyrun::Coverage::Merge.format_console_summary(summary)
        Polyrun::Debug.time("write console summary") { File.write(sum_path, summary_text) }
        Polyrun::Log.print summary_text
      end

      def write_merge_html(merged, out_abs)
        html_path = out_abs.sub(/\.json\z/, ".html")
        html_path = "#{out_abs}.html" if html_path == out_abs
        Polyrun::Debug.time("write HTML report") { File.write(html_path, Polyrun::Coverage::Merge.emit_html(merged)) }
      end

      def merge_coverage_log_finish(elapsed, inputs)
        thr = merge_slow_warn_threshold_seconds
        merge_coverage_warn_if_slow(elapsed, thr, inputs) if thr && elapsed > thr
        return unless @verbose || ENV["POLYRUN_PROFILE_MERGE"] == "1" || Polyrun::Debug.enabled?

        Polyrun::Log.warn format("merge-coverage: finished in %.2fs (%d input fragment(s))", elapsed, inputs.size)
      end

      def merge_coverage_warn_if_slow(elapsed, thr, inputs)
        Polyrun::Log.warn format(
          "merge-coverage: slow merge took %.2fs (warn above %.0fs; typical suites are JSON fragments, not TB-scale data; disable: POLYRUN_MERGE_SLOW_WARN_SECONDS=0)",
          elapsed,
          thr
        )
      end

      def merge_coverage_min_line_gate_below?(merged_path, gate)
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
          log_gate_below_minimum(summary, min) if below
          below
        end
      end

      def log_gate_below_minimum(summary, min)
        Polyrun::Log.warn Polyrun::Coverage::Merge.format_console_summary(summary)
        Polyrun::Log.warn "Polyrun coverage: #{summary[:line_percent].round(2)}% rounds below minimum #{min}% (merged)."
      end
    end
  end
end
