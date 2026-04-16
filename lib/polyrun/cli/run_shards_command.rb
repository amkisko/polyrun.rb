require "optparse"
require "rbconfig"

require_relative "start_bootstrap"
require_relative "failure_commands"
require_relative "run_shards_run"

module Polyrun
  class CLI
    module RunShardsCommand
      include StartBootstrap
      include FailureCommands
      include RunShardsRun

      private

      # Default and upper bound for parallel OS processes (POLYRUN_WORKERS / --workers); see {Polyrun::Config}.

      # Spawns N OS processes (not Ruby threads) with POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL so
      # {Coverage::Collector} writes coverage/polyrun-fragment-worker<N>.json (or shard<S>-worker<W>.json in N×M CI). Merge with merge-coverage.
      def cmd_run_shards(argv, config_path)
        run_shards_run!(argv, config_path)
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

      # Same as parallel-rspec but runs +bundle exec rails test+ or +bundle exec ruby -I test+ after +--+.
      def cmd_parallel_minitest(argv, config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        code = start_bootstrap!(cfg, argv, config_path)
        return code if code != 0

        sep = argv.index("--")
        combined =
          if sep
            head = argv[0...sep]
            tail = argv[sep..]
            head + ["--merge-coverage"] + tail
          else
            argv + ["--merge-coverage", "--"] + minitest_parallel_cmd
          end
        Polyrun::Debug.log_kv(parallel_minitest: "combined argv", argv: combined)
        cmd_run_shards(combined, config_path)
      end

      # Same as parallel-rspec but runs +bundle exec polyrun quick+ after +--+ (one Quick process per shard).
      # Run from the app root with +bundle exec+ so workers resolve the same gem as the parent (same concern as +bundle exec rspec+).
      def cmd_parallel_quick(argv, config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        code = start_bootstrap!(cfg, argv, config_path)
        return code if code != 0

        sep = argv.index("--")
        combined =
          if sep
            head = argv[0...sep]
            tail = argv[sep..]
            head + ["--merge-coverage"] + tail
          else
            argv + ["--merge-coverage", "--", "bundle", "exec", "polyrun", "quick"]
          end
        Polyrun::Debug.log_kv(parallel_quick: "combined argv", argv: combined)
        cmd_run_shards(combined, config_path)
      end

      def minitest_parallel_cmd
        rails_bin = File.expand_path("bin/rails", Dir.pwd)
        if File.file?(rails_bin)
          ["bundle", "exec", "rails", "test"]
        else
          ["bundle", "exec", "ruby", "-I", "test"]
        end
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

      # ENV for a worker process: POLYRUN_SHARD_* plus per-shard database URLs from polyrun.yml or DATABASE_URL.
      # When +matrix_total+ > 1 with multiple local workers, sets +POLYRUN_SHARD_MATRIX_INDEX+ / +POLYRUN_SHARD_MATRIX_TOTAL+
      # so {Coverage::Collector} can name fragments uniquely across CI matrix jobs (NxM sharding).
      def shard_child_env(cfg:, workers:, shard:, matrix_index: nil, matrix_total: nil, failure_fragments: false)
        child_env = ENV.to_h.merge(
          Polyrun::Database::Shard.env_map(shard_index: shard, shard_total: workers)
        )
        child_env["POLYRUN_FAILURE_FRAGMENTS"] = "1" if failure_fragments
        mt = matrix_total.nil? ? 0 : Integer(matrix_total)
        if mt > 1
          if matrix_index.nil?
            Polyrun::Log.warn "polyrun run-shards: matrix_total=#{mt} but matrix_index is nil; omit POLYRUN_SHARD_MATRIX_*"
          else
            child_env["POLYRUN_SHARD_MATRIX_INDEX"] = Integer(matrix_index).to_s
            child_env["POLYRUN_SHARD_MATRIX_TOTAL"] = mt.to_s
          end
        end
        dh = cfg.databases
        if dh.is_a?(Hash) && !dh.empty?
          child_env.merge!(Polyrun::Database::UrlBuilder.env_exports_for_databases(dh, shard_index: shard))
        elsif workers > 1 && (u = ENV["DATABASE_URL"]) && !u.to_s.strip.empty?
          child_env["DATABASE_URL"] = Polyrun::Database::Shard.database_url_with_shard(u, shard)
        end
        child_env
      end

      def cmd_build_paths(config_path)
        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        Polyrun::Partition::PathsBuild.apply!(partition: cfg.partition, cwd: Dir.pwd)
      end
    end
  end
end
