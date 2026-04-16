module Polyrun
  class CLI
    # Spawns and waits on worker processes for +run-shards+ / +ci-shard-*+ fan-out.
    module RunShardsParallelChildren
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

          Polyrun::Log.warn "polyrun run-shards: shard #{shard} → #{paths.size} file(s)" if @verbose
          pid = run_shards_spawn_one_worker(child_env, cmd, paths, hook_cfg)
          pids << {pid: pid, shard: shard}
          Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.spawn shard=#{shard} child_pid=#{pid} spec_files=#{paths.size}")
          Polyrun::Log.warn "polyrun run-shards: started shard #{shard} pid=#{pid} (#{paths.size} file(s))" if parallel
        end
        [pids, nil]
      end
      # rubocop:enable Metrics/AbcSize

      def run_shards_spawn_one_worker(child_env, cmd, paths, hook_cfg)
        if hook_cfg.worker_hooks? && !Polyrun::Hooks.disabled?
          Process.spawn(child_env, "sh", "-c", hook_cfg.build_worker_shell_script(cmd, paths))
        else
          Process.spawn(child_env, *cmd, *paths)
        end
      end

      # @return [Array(Array, Integer)] +[shard_results, after_shard_hook_error_code]+ (0 when all +after_shard+ hooks passed)
      def run_shards_wait_all_children(pids, hook_cfg, ctx)
        workers = ctx[:workers]
        shard_results = []
        after_hook_err = 0
        Polyrun::Debug.time("Process.wait (#{pids.size} worker process(es))") do
          pids.each do |h|
            Process.wait(h[:pid])
            exitstatus = $?.exitstatus
            ok = $?.success?
            Polyrun::Debug.log("[parent pid=#{$$}] run-shards: Process.wait child_pid=#{h[:pid]} shard=#{h[:shard]} exit=#{exitstatus} success=#{ok}")
            env_after = ENV.to_h.merge(
              "POLYRUN_HOOK_ORCHESTRATOR" => "1",
              "POLYRUN_SHARD_INDEX" => h[:shard].to_s,
              "POLYRUN_SHARD_TOTAL" => workers.to_s,
              "POLYRUN_WORKER_EXIT_STATUS" => exitstatus.to_s
            )
            rc = hook_cfg.run_phase_if_enabled(:after_shard, env_after)
            after_hook_err = rc if rc != 0 && after_hook_err == 0
            shard_results << {shard: h[:shard], exitstatus: exitstatus, success: ok}
          end
        rescue Interrupt
          # Do not trap SIGINT: Process.wait raises Interrupt; a trap races and prints Interrupt + SystemExit traces.
          run_shards_shutdown_on_signal!(pids, 130)
        rescue SignalException => e
          raise unless e.signm == "SIGTERM"

          run_shards_shutdown_on_signal!(pids, 143)
        end
        [shard_results, after_hook_err]
      end
    end
  end
end
