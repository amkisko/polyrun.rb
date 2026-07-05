require "json"
require "optparse"

require_relative "../spec_quality"

module Polyrun
  class CLI
    module SpecQualityCommands
      private

      def cmd_merge_spec_quality(argv)
        inputs = []
        output = "coverage/polyrun-spec-quality.json"
        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun merge-spec-quality [-i FILE]... [-o OUT] [FILE...]"
          opts.on("-i", "--input FILE", "Spec quality JSONL fragment (repeatable)") { |f| inputs << f }
          opts.on("-o", "--output PATH", String) { |v| output = v }
        end
        parser.parse!(argv)
        inputs.concat(argv) if inputs.empty?

        if inputs.empty?
          inputs = Dir.glob(Polyrun::SpecQuality::Fragment.glob_pattern).sort
        end

        if inputs.empty?
          Polyrun::Log.warn "merge-spec-quality: need -i FILE or coverage/polyrun-spec-quality-fragment-*.jsonl"
          return 2
        end

        out_abs = File.expand_path(output)
        Polyrun::SpecQuality::Merge.merge_and_write(inputs.map { |p| File.expand_path(p) }, out_abs)
        Polyrun::Log.puts out_abs
        0
      end

      # rubocop:disable Metrics/AbcSize -- report argv + gate output
      def cmd_report_spec_quality(argv)
        input = nil
        out_file = nil
        top = 30
        profile = nil
        config_path = nil
        strict = false
        json_out = false
        plan_paths = []

        OptionParser.new do |opts|
          opts.banner = "usage: polyrun report-spec-quality -i FILE [-o PATH] [--top N] [--profile LIST] [--strict] [--json]"
          opts.on("-i", "--input PATH", "Merged polyrun-spec-quality.json") { |v| input = v }
          opts.on("-o", "--output PATH", "Write report to file instead of stdout") { |v| out_file = v }
          opts.on("--top N", Integer) { |v| top = v }
          opts.on("--profile LIST", "cpu,mem,io,wall (comma-separated)") { |v| profile = v }
          opts.on("-c", "--config PATH", "polyrun_spec_quality.yml path") { |v| config_path = v }
          opts.on("--plan PATH", "Partition plan JSON (repeatable; polyrun plan output per shard)") { |v| plan_paths << v }
          opts.on("--strict", "Exit 1 when gate thresholds fail") { strict = true }
          opts.on("--json", "Write analysis JSON instead of text report") { json_out = true }
        end.parse!(argv)
        input ||= argv.first

        unless input && File.file?(input)
          Polyrun::Log.warn "report-spec-quality: need -i FILE"
          return 2
        end

        merged = JSON.parse(File.read(File.expand_path(input)))
        cfg = load_spec_quality_config(config_path)
        strict = true if cfg["strict"] || strict
        plan_shards = Polyrun::SpecQuality::PlanLoader.load_shards(plan_paths)

        text = if json_out
          JSON.pretty_generate(Polyrun::SpecQuality::Report.analyze(merged, cfg, plan_shards: plan_shards))
        else
          Polyrun::SpecQuality::Report.format_report(
            merged, cfg: cfg, top: top, profile: profile, plan_shards: plan_shards
          )
        end

        if out_file
          File.write(File.expand_path(out_file), text)
          Polyrun::Log.puts File.expand_path(out_file)
        else
          Polyrun::Log.print text
        end

        violations = Polyrun::SpecQuality::Report.gate_violations(merged, cfg)
        if strict && violations.any?
          violations.each { |v| Polyrun::Log.warn "polyrun spec-quality gate: #{v}" }
          return 1
        end

        0
      end
      # rubocop:enable Metrics/AbcSize

      def merge_spec_quality_after_shards(ctx)
        files = merge_spec_quality_fragment_files
        if files.empty?
          Polyrun::Log.warn "polyrun run-shards: --merge-spec-quality: no spec-quality fragments found under coverage (enable spec-quality collection in your test setup)"
          return nil
        end

        out = ctx[:merge_spec_quality_output] || "coverage/polyrun-spec-quality.json"
        Polyrun::Log.warn "polyrun run-shards: merging #{files.size} spec-quality fragment(s) → #{out}"
        Polyrun::SpecQuality::Merge.merge_and_write(files, File.expand_path(out))
        report_spec_quality_after_merge(out, ctx)
        File.expand_path(out)
      end

      def report_spec_quality_after_merge(merged_path, ctx)
        return unless ctx[:report_spec_quality]

        cfg = load_spec_quality_config(ctx[:config_path])
        merged = JSON.parse(File.read(File.expand_path(merged_path)))
        text = Polyrun::SpecQuality::Report.format_report(merged, cfg: cfg)
        Polyrun::Log.print text

        violations = Polyrun::SpecQuality::Report.gate_violations(merged, cfg)
        return if violations.empty?

        violations.each { |v| Polyrun::Log.warn "polyrun spec-quality gate: #{v}" }
      end

      def merge_spec_quality_fragment_files
        Dir.glob(Polyrun::SpecQuality::Fragment.glob_pattern).sort
      end

      def load_spec_quality_config(config_path)
        root = Dir.pwd
        path = config_path
        if path && !path.to_s.empty?
          path = File.expand_path(path, root)
        end
        Polyrun::SpecQuality::Config.load(root: root, config_path: path)
      rescue
        Polyrun::SpecQuality::Config::DEFAULTS.dup
      end
    end
  end
end
