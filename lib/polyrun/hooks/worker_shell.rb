require "shellwords"
require "rbconfig"

module Polyrun
  class Hooks
    # Builds +sh -c+ script for worker processes (shell + Ruby +before_worker+ / +after_worker+).
    module WorkerShell
      # @param cmd [Array<String>] argv before paths
      # @param paths [Array<String>]
      # @return [String] shell script body for +sh -c+ (worker process)
      # rubocop:disable Metrics/AbcSize -- shell + ruby worker hook branches
      def build_worker_shell_script(cmd, paths)
        main = Shellwords.join(cmd + paths)
        rb = RbConfig.ruby
        bw_shell = commands_for(:before_worker)
        aw_shell = commands_for(:after_worker)
        bw_ruby = ruby_registry&.any?(:before_worker)
        aw_ruby = ruby_registry&.any?(:after_worker)

        lines = []
        lines << "export POLYRUN_HOOK_PHASE=before_worker"
        if bw_ruby || bw_shell.any?
          lines << "set -e"
          lines << worker_ruby_line(rb, :before_worker) if bw_ruby
          bw_shell.each { |c| lines << c }
        end
        lines << "set +e"
        lines << main
        lines << "ec=$?"
        lines << "export POLYRUN_HOOK_PHASE=after_worker"
        if aw_ruby || aw_shell.any?
          lines << "set +e"
          aw_shell.each { |c| lines << "( #{c} ) || true" }
          lines << worker_ruby_line(rb, :after_worker, wrap_allow_fail: true) if aw_ruby
        end
        lines << "exit $ec"
        lines.join("\n")
      end
      # rubocop:enable Metrics/AbcSize

      private

      def worker_ruby_line(rb_exe, phase, wrap_allow_fail: false)
        code = %(require "polyrun"; Polyrun::Hooks::WorkerRunner.run!(:#{phase}))
        line = "#{rb_exe} -e #{Shellwords.escape(code)}"
        wrap_allow_fail ? "( #{line} ) || true" : line
      end
    end
  end
end
