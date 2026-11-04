module Polyrun
  class CLI
    # Canonical start skip flags are +POLYRUN_SKIP_PREPARE+ / +POLYRUN_SKIP_DATABASES+.
    # Legacy +POLYRUN_START_SKIP_*+ aliases remain accepted during the deprecation window.
    module SkipEnv
      module_function

      def skip_prepare?(env = ENV)
        truthy?(env, "POLYRUN_SKIP_PREPARE") ||
          legacy_truthy?(env, "POLYRUN_START_SKIP_PREPARE", "POLYRUN_SKIP_PREPARE")
      end

      def skip_databases?(env = ENV)
        truthy?(env, "POLYRUN_SKIP_DATABASES") ||
          legacy_truthy?(env, "POLYRUN_START_SKIP_DATABASES", "POLYRUN_SKIP_DATABASES")
      end

      def truthy?(env, name)
        %w[1 true yes].include?(env[name].to_s.downcase)
      end
      private_class_method :truthy?

      def legacy_truthy?(env, legacy, canonical)
        return false unless truthy?(env, legacy)

        unless truthy?(env, canonical)
          Polyrun::Log.warn "polyrun: #{legacy}=1 is deprecated; use #{canonical}=1"
        end
        true
      end
      private_class_method :legacy_truthy?
    end
  end
end
