module Polyrun
  class CLI
    # Suite / shard / worker shell hooks for +ci-shard-run+ / +ci-shard-rspec+.
    module CiShardHooks
      private

      # rubocop:disable Metrics/AbcSize -- suite hooks + spawn/wait + failure paths
      def ci_shard_run_fanout!(ctx)
        hook_cfg = Polyrun::Hooks.from_config(ctx[:cfg])
        suite_started = false
        exit_code = 1

        begin
          env_suite = ENV.to_h.merge(
            "POLYRUN_HOOK_ORCHESTRATOR" => "1",
            "POLYRUN_SHARD_TOTAL" => ctx[:workers].to_s
          )
          code = hook_cfg.run_phase_if_enabled(:before_suite, env_suite)
          return code if code != 0

          suite_started = true

          pids, spawn_err = run_shards_spawn_workers(ctx, hook_cfg)
          if spawn_err
            exit_code = spawn_err
            return spawn_err
          end
          return 1 if pids.empty?

          run_shards_warn_interleaved(ctx[:parallel], pids.size)
          shard_results, wait_hook_err = run_shards_wait_all_children(pids, hook_cfg, ctx)
          failed = shard_results.reject { |r| r[:success] }.map { |r| r[:shard] }

          if failed.any?
            Polyrun::Log.warn "polyrun ci-shard: finished #{pids.size} worker(s) (some failed)"
            run_shards_log_failed_reruns(failed, shard_results, ctx[:plan], ctx[:parallel], ctx[:workers], ctx[:cmd])
            exit_code = 1
            exit_code = 1 if wait_hook_err != 0
            return exit_code
          end

          exit_code = (wait_hook_err == 0) ? 0 : 1
          Polyrun::Log.warn "polyrun ci-shard: finished #{pids.size} worker(s) (exit 0)" if exit_code == 0
          exit_code
        ensure
          if suite_started
            env_after = ENV.to_h.merge(
              "POLYRUN_HOOK_ORCHESTRATOR" => "1",
              "POLYRUN_SHARD_TOTAL" => ctx[:workers].to_s,
              "POLYRUN_SUITE_EXIT_STATUS" => exit_code.to_s
            )
            hook_cfg.run_phase_if_enabled(:after_suite, env_after)
          end
        end
      end
      # rubocop:enable Metrics/AbcSize

      # One matrix shard, one OS process: same hook phases as +run-shards+ with +--workers 1+ (no +exec+ when hooks exist).
      # rubocop:disable Metrics/AbcSize -- suite / shard / worker lifecycle
      def ci_shard_run_single!(cmd, paths, cfg, pc, _config_path)
        hook_cfg = Polyrun::Hooks.from_config(cfg)
        if hook_cfg.empty? || Polyrun::Hooks.disabled?
          exec(*cmd, *paths)
        end

        si = Polyrun::Config::Resolver.resolve_shard_index(pc)
        st = Polyrun::Config::Resolver.resolve_shard_total(pc)
        suite_started = false
        exit_code = 1
        # Distributed CI matrix (N > 1 global shards): each job is one shard; suite hooks are pipeline-wide.
        # Run them once via +polyrun hook run before_suite+ / +after_suite+ (e.g. dedicated job), or set
        # +POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1+ to run suite hooks on every matrix job.
        matrix_shards = st > 1
        run_suite_hooks = !matrix_shards || Polyrun::Hooks.suite_per_matrix_job?

        begin
          env_orch = ENV.to_h.merge(
            "POLYRUN_HOOK_ORCHESTRATOR" => "1",
            "POLYRUN_SHARD_INDEX" => si.to_s,
            "POLYRUN_SHARD_TOTAL" => st.to_s
          )
          if run_suite_hooks
            code = hook_cfg.run_phase_if_enabled(:before_suite, env_orch)
            return code if code != 0

            suite_started = true
          end

          code = hook_cfg.run_phase_if_enabled(:before_shard, env_orch)
          return code if code != 0

          mx, mt = ci_shard_matrix_context(pc, 1)
          child_env = shard_child_env(cfg: cfg, workers: 1, shard: 0, matrix_index: mx, matrix_total: mt)
          child_env = child_env.merge("POLYRUN_HOOK_ORCHESTRATOR" => "0")
          child_env = hook_cfg.merge_worker_ruby_env(child_env)

          if hook_cfg.worker_hooks? && !Polyrun::Hooks.disabled?
            system(child_env, "sh", "-c", hook_cfg.build_worker_shell_script(cmd, paths))
          else
            system(child_env, *cmd, *paths)
          end
          exit_code = $?.exitstatus

          rc = hook_cfg.run_phase_if_enabled(:after_shard, env_orch.merge(
            "POLYRUN_WORKER_EXIT_STATUS" => exit_code.to_s
          ))
          exit_code = rc if rc != 0

          exit_code
        ensure
          if suite_started
            hook_cfg.run_phase_if_enabled(:after_suite, env_orch.merge(
              "POLYRUN_SUITE_EXIT_STATUS" => exit_code.to_s
            ))
          end
        end
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
