require "fileutils"

require_relative "run_shards_parallel_wait"

module Polyrun
  class CLI
    # Spawns worker processes for +run-shards+ / +ci-shard-*+ fan-out. See {RunShardsParallelWait} for wait/timeout.
    module RunShardsParallelChildren
      include RunShardsParallelWait

      private

      # @return [Array(Array, Integer, nil)] +[pids, spawn_error_code]+; +spawn_error_code+ is +nil+ when all spawns succeeded
      # rubocop:disable Metrics/AbcSize -- shard loop: spawn + shard hooks + env
      def run_shards_spawn_workers(ctx, hook_cfg)
        workers = ctx[:workers]
        cmd = ctx[:cmd]
        cfg = ctx[:cfg]
        plan = ctx[:plan]
        parallel = ctx[:parallel]
        mx = ctx[:matrix_shard_index]
        mt = ctx[:matrix_shard_total]

        pids = []
        workers.times do |shard|
          paths = plan.shard(shard)
          if paths.empty?
            Polyrun::Log.warn "polyrun run-shards: shard #{shard} skipped (no paths)" if @verbose || parallel
            next
          end

          env_shard = ENV.to_h.merge(
            "POLYRUN_HOOK_ORCHESTRATOR" => "1",
            "POLYRUN_SHARD_INDEX" => shard.to_s,
            "POLYRUN_SHARD_TOTAL" => workers.to_s
          )
          code = hook_cfg.run_phase_if_enabled(:before_shard, env_shard)
          if code != 0
            run_shards_terminate_children!(pids)
            return [pids, code]
          end

          child_env = shard_child_env(
            cfg: cfg,
            workers: workers,
            shard: shard,
            matrix_index: mx,
            matrix_total: mt,
            failure_fragments: ctx[:merge_failures]
          )
          child_env = child_env.merge("POLYRUN_HOOK_ORCHESTRATOR" => "0")
          child_env = hook_cfg.merge_worker_ruby_env(child_env)

          ping_path = run_shards_prepare_worker_ping!(ctx, child_env, shard)

          Polyrun::Log.warn "polyrun run-shards: shard #{shard} → #{paths.size} file(s)" if @verbose
          spawned_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          pid = run_shards_spawn_one_worker(child_env, cmd, paths, hook_cfg)
          pids << {pid: pid, shard: shard, spawned_at: spawned_at, ping_path: ping_path}
          Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.spawn shard=#{shard} child_pid=#{pid} spec_files=#{paths.size}")
          Polyrun::Log.warn "polyrun run-shards: started shard #{shard} pid=#{pid} (#{paths.size} file(s))" if parallel
        end
        [pids, nil]
      end
      # rubocop:enable Metrics/AbcSize

      def run_shards_prepare_worker_ping!(ctx, child_env, shard)
        idle_sec = ctx[:worker_idle_timeout_sec]
        idle_sec = nil if idle_sec.is_a?(Numeric) && idle_sec <= 0
        return nil unless idle_sec

        dir = File.join(Dir.pwd, "tmp", "polyrun")
        FileUtils.mkdir_p(dir)
        path = File.expand_path("worker-ping-#{$$}-#{shard}.txt", dir)
        File.binwrite(path, "")
        child_env["POLYRUN_WORKER_PING_FILE"] = path
        interval = ENV["POLYRUN_WORKER_PING_INTERVAL_SEC"].to_s.strip
        child_env["POLYRUN_WORKER_PING_INTERVAL_SEC"] = interval.empty? ? "15" : interval
        path
      end

      def run_shards_spawn_one_worker(child_env, cmd, paths, hook_cfg)
        if hook_cfg.worker_hooks? && !Polyrun::Hooks.disabled?
          Process.spawn(child_env, "sh", "-c", hook_cfg.build_worker_shell_script(cmd, paths))
        else
          Process.spawn(child_env, *cmd, *paths)
        end
      end
    end
  end
end
