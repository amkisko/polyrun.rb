require "open3"

module Polyrun
  class Hooks
    # Runs shell hook commands; suppresses stdout/stderr on success unless verbose.
    module ShellRunner
      private

      def run_shell_hook(cmd, merged)
        if hook_shell_output_verbose?
          ok = system(merged, "sh", "-c", cmd)
          return [ok, $?.exitstatus]
        end

        stdout, stderr, status = Open3.capture3(merged, "sh", "-c", cmd)
        unless status.success?
          $stdout.print(stdout) unless stdout.empty?
          $stderr.print(stderr) unless stderr.empty?
        end
        [status.success?, status.exitstatus]
      rescue Interrupt
        Polyrun::Log.warn "polyrun hooks: shell hook interrupted"
        [false, 130]
      end

      def hook_shell_output_verbose?
        Polyrun::Debug.enabled? ||
          %w[1 true yes].include?(ENV["POLYRUN_VERBOSE"]&.to_s&.downcase) ||
          %w[1 true yes].include?(ENV["POLYRUN_HOOKS_VERBOSE"]&.to_s&.downcase)
      end
    end
  end
end
