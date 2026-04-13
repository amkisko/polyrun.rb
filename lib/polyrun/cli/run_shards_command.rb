require "optparse"
require "rbconfig"

require_relative "start_bootstrap"

module Polyrun
  class CLI
    module RunShardsCommand
      include StartBootstrap

      private

      # Default and upper bound for parallel OS processes (POLYRUN_WORKERS / --workers).
      DEFAULT_PARALLEL_WORKERS = 5
      MAX_PARALLEL_WORKERS = 10

      # Spawns N OS processes (not Ruby threads) with POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL so
      # {Coverage::Collector} writes coverage/polyrun-fragment-<shard>.json. Merge with merge-coverage.
      def cmd_run_shards(argv, config_path)
        require "shellwords"

        workers = env_int("POLYRUN_WORKERS", DEFAULT_PARALLEL_WORKERS)
        paths_file = nil
        run_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        sep = argv.index("--")
        unless sep
          Polyrun::Log.warn "polyrun run-shards: need -- before the command (e.g. run-shards --workers 5 -- bundle exec rspec)"
          return 2
        end

        head = argv[0...sep]
        cmd = argv[(sep + 1)..].map(&:to_s)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        pc = cfg.partition
        strategy = (pc["strategy"] || pc[:strategy] || "round_robin").to_s
        seed = pc["seed"] || pc[:seed]
        timing_path = nil
        constraints_path = nil
        merge_coverage = false
        merge_output = nil
        merge_format = nil

        parser = OptionParser.new do |opts|
          opts.banner = "usage: polyrun run-shards [--workers N] [--strategy NAME] [--paths-file P] [--timing P] [--constraints P] [--seed S] [--merge-coverage] [--merge-output P] [--merge-format LIST] [--] <command> [args...]"
          opts.on("--workers N", Integer) { |v| workers = v }
          opts.on("--strategy NAME", String) { |v| strategy = v }
          opts.on("--seed VAL") { |v| seed = v }
          opts.on("--paths-file PATH", String) { |v| paths_file = v }
          opts.on("--constraints PATH", String) { |v| constraints_path = v }
          opts.on("--timing PATH", "merged polyrun_timing.json; implies cost_binpack unless hrw/cost") { |v| timing_path = v }
          opts.on("--merge-coverage", "After success, merge coverage/polyrun-fragment-*.json (Polyrun coverage must be enabled)") { merge_coverage = true }
          opts.on("--merge-output PATH", String) { |v| merge_output = v }
          opts.on("--merge-format LIST", String) { |v| merge_format = v }
        end
        parser.parse!(head)

        paths_file ||= pc["paths_file"] || pc[:paths_file]
        code = Polyrun::Partition::PathsBuild.apply!(partition: pc, cwd: Dir.pwd)
        return code if code != 0

        unless timing_path
          tf = pc["timing_file"] || pc[:timing_file]
          if tf && (Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy))
            timing_path = tf
          end
        end

        if workers < 1
          Polyrun::Log.warn "polyrun run-shards: --workers must be >= 1"
          return 2
        end

        if workers > MAX_PARALLEL_WORKERS
          Polyrun::Log.warn "polyrun run-shards: capping --workers / POLYRUN_WORKERS from #{workers} to #{MAX_PARALLEL_WORKERS}"
          workers = MAX_PARALLEL_WORKERS
        end

        if cmd.empty?
          Polyrun::Log.warn "polyrun run-shards: empty command after --"
          return 2
        end

        cmd = Shellwords.split(cmd.first) if cmd.size == 1 && cmd.first.include?(" ")

        resolved = Polyrun::Partition::Paths.resolve_run_shard_items(paths_file: paths_file)
        if resolved[:error]
          Polyrun::Log.warn "polyrun run-shards: #{resolved[:error]}"
          return 2
        end
        items = resolved[:items]
        paths_source = resolved[:source]
        Polyrun::Log.warn "polyrun run-shards: #{items.size} spec path(s) from #{paths_source}"

        if items.empty?
          Polyrun::Log.warn "polyrun run-shards: no spec paths (spec/spec_paths.txt, partition.paths_file, or spec/**/*_spec.rb)"
          return 2
        end

        costs = nil
        if timing_path
          costs = Polyrun::Partition::Plan.load_timing_costs(File.expand_path(timing_path.to_s, Dir.pwd))
          if costs.empty?
            Polyrun::Log.warn "polyrun run-shards: timing file missing or empty: #{timing_path}"
            return 2
          end
          unless Polyrun::Partition::Plan.cost_strategy?(strategy) || Polyrun::Partition::Plan.hrw_strategy?(strategy)
            Polyrun::Log.warn "polyrun run-shards: using cost_binpack (timing data present)" if @verbose
            strategy = "cost_binpack"
          end
        elsif Polyrun::Partition::Plan.cost_strategy?(strategy)
          Polyrun::Log.warn "polyrun run-shards: --timing or partition.timing_file required for strategy #{strategy}"
          return 2
        end

        Polyrun::Debug.log_kv(
          run_shards: "ready to partition",
          workers: workers,
          strategy: strategy,
          merge_coverage: merge_coverage,
          command: cmd,
          timing_path: timing_path,
          paths_source: paths_source,
          item_count: items.size
        )

        constraints = load_partition_constraints(pc, constraints_path)

        plan = Polyrun::Debug.time("Partition::Plan.new (partition #{items.size} paths → #{workers} shards)") do
          Polyrun::Partition::Plan.new(
            items: items,
            total_shards: workers,
            strategy: strategy,
            seed: seed,
            costs: costs,
            constraints: constraints,
            root: Dir.pwd
          )
        end

        if Polyrun::Debug.enabled?
          workers.times do |s|
            n = plan.shard(s).size
            Polyrun::Debug.log("run-shards: shard #{s} → #{n} spec file(s)")
          end
        end

        Polyrun::Log.warn "polyrun run-shards: #{items.size} paths → #{workers} workers (#{strategy})" if @verbose

        parallel = workers > 1
        if parallel
          Polyrun::Log.warn <<~MSG
            polyrun run-shards: #{items.size} spec path(s) -> #{workers} parallel worker processes (not Ruby threads); strategy=#{strategy}
            (plain `bundle exec rspec` is one process; this command fans out.)
          MSG
        end

        pids = []
        workers.times do |shard|
          paths = plan.shard(shard)
          if paths.empty?
            Polyrun::Log.warn "polyrun run-shards: shard #{shard} skipped (no paths)" if @verbose || parallel
            next
          end

          child_env = ENV.to_h.merge(
            Polyrun::Database::Shard.env_map(shard_index: shard, shard_total: workers)
          )
          dh = cfg.databases
          if dh.is_a?(Hash) && !dh.empty?
            child_env.merge!(Polyrun::Database::UrlBuilder.env_exports_for_databases(dh, shard_index: shard))
          elsif workers > 1 && (u = ENV["DATABASE_URL"]) && !u.to_s.strip.empty?
            child_env["DATABASE_URL"] = Polyrun::Database::Shard.database_url_with_shard(u, shard)
          end

          Polyrun::Log.warn "polyrun run-shards: shard #{shard} → #{paths.size} file(s)" if @verbose
          pid = Process.spawn(child_env, *cmd, *paths)
          pids << {pid: pid, shard: shard}
          Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.spawn shard=#{shard} child_pid=#{pid} spec_files=#{paths.size}")
          Polyrun::Log.warn "polyrun run-shards: started shard #{shard} pid=#{pid} (#{paths.size} file(s))" if parallel
        end

        if pids.empty?
          Polyrun::Log.warn "polyrun run-shards: no processes started"
          return 1
        end

        if parallel && pids.size > 1
          Polyrun::Log.warn "polyrun run-shards: #{pids.size} children running; RSpec output below may be interleaved."
        end

        failed = []
        Polyrun::Debug.time("Process.wait (#{pids.size} worker process(es))") do
          pids.each do |h|
            Process.wait(h[:pid])
            ok = $?.success?
            Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.wait child_pid=#{h[:pid]} shard=#{h[:shard]} exit=#{$?.exitstatus} success=#{ok}")
            failed << h[:shard] unless ok
          end
        end

        Polyrun::Debug.log(format(
          "run-shards: workers wall time since start: %.3fs",
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_t0
        ))

        if parallel
          Polyrun::Log.warn "polyrun run-shards: finished #{pids.size} worker(s)" + (failed.any? ? " (some failed)" : " (exit 0)")
        end

        if failed.any?
          Polyrun::Log.warn "polyrun run-shards: failed shard(s): #{failed.sort.join(", ")}"
          return 1
        end

        if merge_coverage
          mo = merge_output || "coverage/merged.json"
          mf = merge_format || ENV["POLYRUN_MERGE_FORMATS"] || Polyrun::Coverage::Reporting::DEFAULT_MERGE_FORMAT_LIST
          Polyrun::Debug.log("run-shards: starting post-worker merge_coverage_after_shards → #{mo}")
          return merge_coverage_after_shards(output: mo, format_list: mf, config_path: config_path)
        end

        if parallel
          Polyrun::Log.warn <<~MSG
            polyrun run-shards: coverage — each worker writes coverage/polyrun-fragment-<shard>.json when Polyrun coverage is enabled (POLYRUN_SHARD_INDEX per process).
            polyrun run-shards: next step — merge with: polyrun merge-coverage -i 'coverage/polyrun-fragment-*.json' -o coverage/merged.json --format json,cobertura,console
          MSG
        end
        0
      end

      # Same as run-shards with --merge-coverage; if you omit --, runs `bundle exec rspec`.
      def cmd_parallel_rspec(argv, config_path)
        sep = argv.index("--")
        combined =
          if sep
            head = argv[0...sep]
            tail = argv[sep..]
            head + ["--merge-coverage"] + tail
          else
            argv + ["--merge-coverage", "--", "bundle", "exec", "rspec"]
          end
        Polyrun::Debug.log_kv(parallel_rspec: "combined argv", argv: combined)
        cmd_run_shards(combined, config_path)
      end

      # Convenience alias: optional legacy script/build_spec_paths.rb (if present and partition.paths_build unset), then parallel-rspec.
      def cmd_start(argv, config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        code = start_bootstrap!(cfg, argv, config_path)
        return code if code != 0

        unless skip_build_spec_paths?
          unless partition_paths_build?(cfg.partition)
            build_script = File.expand_path("script/build_spec_paths.rb", Dir.pwd)
            if File.file?(build_script)
              ok = system({"RUBYOPT" => nil}, RbConfig.ruby, build_script)
              return 1 unless ok
            end
          end
        end
        cmd_parallel_rspec(argv, config_path)
      end

      def partition_paths_build?(partition)
        pb = partition["paths_build"] || partition[:paths_build]
        pb.is_a?(Hash) && !pb.empty?
      end

      def skip_build_spec_paths?
        v = ENV["POLYRUN_SKIP_BUILD_SPEC_PATHS"].to_s.downcase
        %w[1 true yes].include?(v)
      end

      def cmd_build_paths(config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        Polyrun::Partition::PathsBuild.apply!(partition: cfg.partition, cwd: Dir.pwd)
      end
    end
  end
end
