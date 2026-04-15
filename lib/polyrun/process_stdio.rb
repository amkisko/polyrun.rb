require "tempfile"

module Polyrun
  # Run a subprocess without +Open3+ pipe reader threads (avoids noisy +IOError+s on SIGINT when
  # streams close). By default stdin/stdout/stderr are inherited so output streams live and the
  # child can use the TTY for prompts.
  module ProcessStdio
    MAX_FAILURE_CAPTURE_BYTES = 32_768

    class << self
      # @param env [Hash, nil] optional environment for the child (only forwarded when a Hash)
      # @param argv [Array<String>] command argv
      # @param silent [Boolean] if true, connect stdin/stdout/stderr to +File::NULL+ (no terminal output;
      #   non-interactive). Still no Open3 pipe threads.
      # @return [Process::Status]
      def inherit_stdio_spawn_wait(env, *argv, chdir: nil, silent: false)
        st, = spawn_wait(env, *argv, chdir: chdir, silent: silent)
        st
      end

      # Like {#inherit_stdio_spawn_wait}, but returns captured stdout/stderr when +silent+ is true.
      # On success those strings are empty (not read). When +silent+ is false, output goes to the TTY
      # and returned captures are empty.
      #
      # @return [Array(Process::Status, String, String)] status, stdout capture, stderr capture
      def spawn_wait(env, *argv, chdir: nil, silent: false)
        args = spawn_argv(env, *argv)
        return spawn_wait_inherit(args, chdir) unless silent

        spawn_wait_silent(args, chdir)
      end

      # Builds a diagnostic string for failed subprocesses (used when +silent: true+ hid live output).
      def format_failure_message(label, status, stdout, stderr)
        msg = "#{label} failed (exit #{status.exitstatus})"
        s = stdout.to_s
        e = stderr.to_s
        msg << "\n--- stdout ---\n#{s}" unless s.strip.empty?
        msg << "\n--- stderr ---\n#{e}" unless e.strip.empty?
        msg
      end

      private

      def spawn_argv(env, *argv)
        a = []
        a << env if env.is_a?(Hash)
        a.concat(argv)
        a
      end

      def spawn_wait_inherit(args, chdir)
        opts = {in: :in, out: :out, err: :err}
        opts[:chdir] = chdir if chdir
        pid = Process.spawn(*args, **opts)
        st = Process.wait2(pid).last
        [st, "", ""]
      end

      def spawn_wait_silent(args, chdir)
        Tempfile.create("polyrun-out") do |tfout|
          Tempfile.create("polyrun-err") do |tferr|
            tfout.close
            tferr.close
            out_path = tfout.path
            err_path = tferr.path
            opts = {in: File::NULL, out: out_path, err: err_path}
            opts[:chdir] = chdir if chdir
            pid = Process.spawn(*args, **opts)
            st = Process.wait2(pid).last
            if st.success?
              [st, "", ""]
            else
              out = File.binread(out_path)
              err = File.binread(err_path)
              [st, truncate_failure_capture(out), truncate_failure_capture(err)]
            end
          end
        end
      end

      def truncate_failure_capture(bytes)
        s = bytes.to_s
        return s if s.bytesize <= MAX_FAILURE_CAPTURE_BYTES

        tail = s.byteslice(-MAX_FAILURE_CAPTURE_BYTES, MAX_FAILURE_CAPTURE_BYTES)
        "... (#{s.bytesize} bytes total; showing last #{MAX_FAILURE_CAPTURE_BYTES} bytes)\n" + tail
      end
    end
  end
end
