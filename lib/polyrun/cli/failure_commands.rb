require "json"
require "fileutils"
require "optparse"

require_relative "../reporting/failure_merge"

module Polyrun
  class CLI
    module FailureCommands
      private

      def cmd_merge_failures(argv, _config_path)
        inputs, output, format = merge_failures_parse_argv(argv)
        if inputs.empty?
          Polyrun::Log.warn "merge-failures: need at least one existing -i FILE (after glob expansion)"
          return 2
        end
        Polyrun::Log.warn "merge-failures: merging #{inputs.size} fragment(s)" if @verbose
        n = merge_failures_merge_files_or_warn!(inputs, output: output, format: format)
        return 1 if n.nil?

        Polyrun::Log.puts File.expand_path(output)
        Polyrun::Log.warn "merge-failures: #{n} failure row(s)" if @verbose
        0
      end

      def merge_failures_merge_files_or_warn!(inputs, output:, format:)
        Polyrun::Reporting::FailureMerge.merge_files!(inputs, output: output, format: format)
      rescue Polyrun::Error => e
        Polyrun::Log.warn e.message.to_s
        nil
      end

      def merge_failures_parse_argv(argv)
        inputs = []
        output = File.join("tmp", "polyrun_failures", "merged.jsonl")
        format = "jsonl"
        OptionParser.new do |opts|
          opts.banner = "usage: polyrun merge-failures -i FILE [-i FILE] [-o PATH] [--format jsonl|json]"
          opts.on("-i", "--input FILE", "JSONL fragment or RSpec JSON (repeatable; globs ok)") do |f|
            expand_merge_input_pattern(f).each { |x| inputs << x }
          end
          opts.on("-o", "--output PATH", String) { |v| output = v }
          opts.on("--format VAL", "jsonl (default) or json") { |v| format = v }
        end.parse!(argv)
        inputs.uniq!
        inputs.select! { |p| File.file?(p) }
        [inputs, output, format]
      end

      # After run-shards workers exit: merge polyrun failure fragments when requested.
      # Runs even when shards failed (unlike --merge-coverage).
      # @return [String, nil] absolute path to merged file, or nil when skipped / nothing written
      def merge_failures_after_shards(ctx)
        return nil unless ctx[:merge_failures]

        pattern = Polyrun::Reporting::FailureMerge.default_fragment_glob
        files = Dir.glob(pattern).sort
        if files.empty?
          Polyrun::Log.warn "polyrun run-shards: --merge-failures: no #{Polyrun::Reporting::FailureMerge::FRAGMENT_GLOB} under fragment dir (enable Polyrun::RSpec.install_failure_fragments! in spec_helper?)"
          return nil
        end

        fmt = merge_failures_resolved_format(ctx)
        out = merge_failures_resolved_output_path(ctx, fmt)
        Polyrun::Log.warn "polyrun run-shards: merging #{files.size} failure fragment(s) → #{out} (#{fmt})"
        Polyrun::Debug.log_kv(merge_failures: "start", output: out, inputs: files, format: fmt)
        n = Polyrun::Reporting::FailureMerge.merge_files!(files, output: out, format: fmt)
        Polyrun::Debug.log_kv(merge_failures: "done", rows: n, output: File.expand_path(out))
        File.expand_path(out)
      end

      def merge_failures_resolved_format(ctx)
        f = ctx[:merge_failures_format].to_s.strip.downcase
        return "jsonl" if f.empty?
        return "jsonl" if f == "jsonl"
        return "json" if f == "json"

        Polyrun::Log.warn "polyrun run-shards: unknown merge_failures_format=#{ctx[:merge_failures_format].inspect}; using jsonl"
        "jsonl"
      end

      def merge_failures_resolved_output_path(ctx, fmt)
        raw = ctx[:merge_failures_output]
        return File.expand_path(raw) if raw && !raw.to_s.strip.empty?

        ext = (fmt == "json") ? "json" : "jsonl"
        File.expand_path(File.join("tmp", "polyrun_failures", "merged.#{ext}"))
      end
    end
  end
end
