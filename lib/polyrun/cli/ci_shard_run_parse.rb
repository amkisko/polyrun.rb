module Polyrun
  class CLI
    # Parsing for +ci-shard-run+ / +ci-shard-rspec+ plan argv (+--shard-processes+, +--workers+).
    module CiShardRunParse
      private

      # Strips +--shard-processes+ / +--workers+ from +plan_argv+ and returns +[count, exit_code]+.
      # +exit_code+ is +nil+ on success, +2+ on invalid or missing integer (no exception).
      # Does not use +OptionParser+ so +plan+ flags (+--shard+, +--total+, …) pass through unchanged.
      # Note: +--workers+ here means processes for this matrix job (+POLYRUN_SHARD_PROCESSES+), not +run-shards+ +POLYRUN_WORKERS+.
      def ci_shard_parse_shard_processes!(plan_argv, pc)
        workers = Polyrun::Config::Resolver.resolve_shard_processes(pc)
        rest = []
        i = 0
        while i < plan_argv.size
          case plan_argv[i]
          when "--shard-processes"
            n, err = ci_shard_parse_positive_int_flag!(plan_argv, i, "--shard-processes")
            return [nil, err] if err

            workers = n
            i += 2
          when "--workers"
            n, err = ci_shard_parse_positive_int_flag!(plan_argv, i, "--workers")
            return [nil, err] if err

            workers = n
            i += 2
          else
            rest << plan_argv[i]
            i += 1
          end
        end
        plan_argv.replace(rest)
        [workers, nil]
      end

      # @return [Array(Integer or nil, Integer or nil)] +[value, exit_code]+ — +exit_code+ is +nil+ on success, +2+ on error
      def ci_shard_parse_positive_int_flag!(argv, i, flag_name)
        arg = argv[i + 1]
        if arg.nil?
          Polyrun::Log.warn "polyrun ci-shard: missing value for #{flag_name}"
          return [nil, 2]
        end
        n = Integer(arg, exception: false)
        if n.nil?
          Polyrun::Log.warn "polyrun ci-shard: #{flag_name} must be an integer (got #{arg.inspect})"
          return [nil, 2]
        end
        [n, nil]
      end

      # @return [Array(Integer, Integer, nil)] +[capped_workers, exit_code]+ — +exit_code+ is +nil+ when OK
      def ci_shard_normalize_shard_processes(workers)
        if workers < 1
          Polyrun::Log.warn "polyrun ci-shard: --shard-processes / --workers must be >= 1"
          return [workers, 2]
        end
        w = workers
        if w > Polyrun::Config::MAX_PARALLEL_WORKERS
          Polyrun::Log.warn "polyrun ci-shard: capping --shard-processes / --workers from #{w} to #{Polyrun::Config::MAX_PARALLEL_WORKERS}"
          w = Polyrun::Config::MAX_PARALLEL_WORKERS
        end
        [w, nil]
      end
    end
  end
end
