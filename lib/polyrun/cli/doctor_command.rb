require_relative "../coverage/config_resolve"
require_relative "skip_env"

module Polyrun
  class CLI
    module DoctorCommand
      private

      def cmd_doctor(argv, config_path)
        unless argv.empty?
          Polyrun::Log.warn "polyrun doctor: unexpected arguments: #{argv.join(" ")}"
          return 2
        end

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        lines = doctor_lines(cfg)
        lines.each { |line| Polyrun::Log.puts line }
        0
      end

      def doctor_lines(cfg)
        workers = Polyrun::Config::Resolver.parallel_worker_count(cfg).clamp(1, Polyrun::Config::MAX_PARALLEL_WORKERS)
        cov = Polyrun::Coverage::ConfigResolve.load(root: Dir.pwd, polyrun_config_path: cfg.path)
        lines = []
        lines << "polyrun doctor"
        lines << "  config: #{cfg.path || "(none)"}"
        lines << "  suite: #{cfg.suite || "(none)"}"
        lines << "  workers: #{workers}"
        lines.concat(doctor_start_lines(cfg))
        lines.concat(doctor_database_lines(cfg, workers))
        lines.concat(doctor_coverage_lines(cov))
        lines.concat(doctor_warning_lines(cfg, workers))
        lines
      end

      def doctor_start_lines(cfg)
        prep = start_run_prepare?(cfg)
        dbs = start_databases_provision_wanted?(cfg)
        [
          "  start.prepare: #{doctor_yes_no(prep, SkipEnv.skip_prepare?)}",
          "  start.databases: #{doctor_yes_no(dbs, SkipEnv.skip_databases?)}"
        ]
      end

      def doctor_yes_no(wanted, skipped)
        text = wanted ? "yes" : "no"
        skipped ? "#{text} (skipped by env)" : text
      end

      def doctor_database_lines(cfg, workers)
        dh = cfg.databases
        return ["  databases: (none)"] unless dh.is_a?(Hash) && !dh.empty?

        adapter = Polyrun::Database::UrlBuilder::ConnectionInfer.infer_adapter_name(dh)
        lines = ["  databases.adapter: #{adapter || "(unknown)"}"]
        if adapter == "postgresql"
          names = (0...workers).map do |i|
            Polyrun::Database::UrlBuilder.shard_database_name(dh, shard_index: i)
          rescue Polyrun::Error
            nil
          end.compact
          lines << "  databases.shards: #{names.join(", ")}" unless names.empty?
          lines << "  databases.provision: CloneShards (PostgreSQL)"
        else
          lines << "  databases.provision: URL shaping only (no auto clone)"
        end
        lines
      rescue Polyrun::Error => e
        ["  databases: error (#{e.message})"]
      end

      def doctor_coverage_lines(cov)
        disable = %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_DISABLE"].to_s.downcase)
        [
          "  coverage.source: #{cov["coverage_config_source"] || "none"}",
          "  coverage.disable: #{disable ? "yes (POLYRUN_COVERAGE_DISABLE)" : "no"}"
        ]
      end

      def doctor_warning_lines(cfg, workers)
        warnings = []
        matrix_total = ENV["POLYRUN_SHARD_TOTAL"].to_s
        if !matrix_total.empty? && matrix_total.to_i > 1 && workers > 1
          warnings << "  warn: matrix POLYRUN_SHARD_TOTAL=#{matrix_total} and in-process workers=#{workers} are both set; confirm fragment naming and merge story"
        end
        suite_files = Dir.glob("polyrun.*.yml").reject { |p| p == "polyrun.yml" }
        if cfg.path && !suite_files.empty? && cfg.suite.nil?
          warnings << "  warn: named suite files present (#{suite_files.sort.join(", ")}); prefer suites: in root polyrun.yml + --suite"
        end
        warnings
      end
    end
  end
end
