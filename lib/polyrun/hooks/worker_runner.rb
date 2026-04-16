require_relative "../log"

module Polyrun
  class Hooks
    # Invoked by worker shell wrapper (+ruby -e+). Requires +POLYRUN_HOOKS_RUBY_FILE+.
    module WorkerRunner
      module_function

      # @return [Integer] exit code (0 on success)
      def run!(phase)
        phase = phase.to_sym
        path = ENV["POLYRUN_HOOKS_RUBY_FILE"]
        return 0 if path.nil? || path.empty?

        registry = Dsl.load_registry(path)
        return 0 if registry.nil? || !registry.any?(phase)

        env = ENV.to_h
        registry.run(phase, env)
        0
      rescue => e
        Polyrun::Log.warn "polyrun hooks worker #{phase}: #{e.class}: #{e.message}"
        1
      end
    end
  end
end
