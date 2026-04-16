module Polyrun
  class CLI
    # +polyrun hook run <phase>+ — run one lifecycle phase from +polyrun.yml+ +hooks:+ (manual debugging / CI).
    module HooksCommand
      private

      def cmd_hook(argv, config_path)
        sub = argv.shift
        case sub
        when "run"
          cmd_hook_run(argv, config_path)
        when nil, "help", "-h", "--help"
          print_hook_help
          0
        else
          Polyrun::Log.warn "polyrun hook: unknown subcommand #{sub.inspect} (try: polyrun hook run <phase>)"
          print_hook_help
          2
        end
      end

      def cmd_hook_run(argv, config_path)
        phase = argv.shift
        if phase.nil? || phase == "-h" || phase == "--help"
          print_hook_help
          return 2
        end

        shard, total = hook_run_parse_shard_flags!(argv)

        unless argv.empty?
          Polyrun::Log.warn "polyrun hook run: unexpected arguments: #{argv.inspect}"
          return 2
        end

        phase_sym = Polyrun::Hooks.parse_phase(phase)
        unless phase_sym && Polyrun::Hooks::PHASES.include?(phase_sym)
          Polyrun::Log.warn "polyrun hook run: unknown phase #{phase.inspect} (expected: #{Polyrun::Hooks::PHASES.join(", ")})"
          return 2
        end

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        hook_cfg = Polyrun::Hooks.from_config(cfg)
        env = hook_run_env(shard, total)

        hook_cfg.run_phase(phase_sym, env)
      rescue ArgumentError => e
        Polyrun::Log.warn "polyrun hook run: #{e.message}"
        2
      end

      def hook_run_parse_shard_flags!(argv)
        shard = nil
        total = nil
        while (a = argv.first)
          case a
          when "--shard"
            argv.shift
            shard = Integer(argv.shift || (raise ArgumentError, "--shard needs a value"))
          when "--total"
            argv.shift
            total = Integer(argv.shift || (raise ArgumentError, "--total needs a value"))
          else
            break
          end
        end
        [shard, total]
      end

      def hook_run_env(shard, total)
        env = ENV.to_h.merge(
          "POLYRUN_HOOK_ORCHESTRATOR" => "1",
          "POLYRUN_HOOK_CLI" => "1"
        )
        env["POLYRUN_SHARD_INDEX"] = shard.to_s unless shard.nil?
        env["POLYRUN_SHARD_TOTAL"] = total.to_s unless total.nil?
        env
      end

      def print_hook_help
        Polyrun::Log.puts <<~HELP
          usage: polyrun hook run <phase> [--shard N] [--total M]

          Runs hook(s) from polyrun.yml: Ruby DSL (+hooks.ruby+) then shell strings for <phase> (same names as RSpec lifecycle:
          before_suite / after_suite as before(:suite) / after(:suite); before_shard / after_shard as
          before(:all) / after(:all); before_worker / after_worker as before(:each) / after(:each)).

          Phases: #{Polyrun::Hooks::PHASES.join(", ")}

          Optional --shard / --total set POLYRUN_SHARD_INDEX / POLYRUN_SHARD_TOTAL for the hook process.
          POLYRUN_HOOKS_DISABLE=1 skips hooks during run-shards / ci-shard only; polyrun hook run still executes.
          For CI matrix (POLYRUN_SHARD_TOTAL > 1), ci-shard-run skips before_suite / after_suite unless POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1; run those phases here or in a dedicated CI job.
        HELP
      end
    end
  end
end
