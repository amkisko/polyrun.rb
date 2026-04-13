module Polyrun
  class CLI
    module QuickCommand
      private

      def cmd_quick(argv)
        require_relative "../quick/runner"
        paths = argv.dup
        Polyrun::Quick::Runner.run(paths: paths.empty? ? nil : paths, verbose: @verbose)
      end
    end
  end
end
