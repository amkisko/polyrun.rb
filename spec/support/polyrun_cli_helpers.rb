require "open3"
require "stringio"

module PolyrunCliHelpers
  PolyrunCliExitStatus = Struct.new(:ok, :exitstatus) do
    def success?
      ok
    end
  end
  # When POLYRUN_COVERAGE=1, run the CLI in-process so stdlib Coverage attributes
  # hits to lib/polyrun/cli/*.rb (subprocess tests do not). Set POLYRUN_CLI_SUBPROCESS=1
  # to force bin/polyrun (e.g. debugging).
  def polyrun(*args, in_process: nil, env: nil)
    root = File.expand_path("../..", __dir__)
    bin = File.join(root, "bin", "polyrun")
    merged = {"RUBYOPT" => nil}.merge(env || {})
    use_ip = if !in_process.nil?
      in_process
    else
      ENV["POLYRUN_COVERAGE"] == "1" && ENV["POLYRUN_CLI_SUBPROCESS"] != "1"
    end

    if use_ip
      polyrun_in_process(merged, *args)
    else
      Open3.capture2e(merged, "ruby", bin, *args)
    end
  end

  def polyrun_in_process(merged_env, *args)
    out = StringIO.new
    err = StringIO.new
    saved = {}
    begin
      merged_env.each do |k, v|
        saved[k] = ENV[k]
        ENV[k] = v
      end
      Polyrun::Log.stdout = out
      Polyrun::Log.stderr = err
      code = Polyrun::CLI.run(args)
      c = code.nil? ? 0 : code.to_i
      [out.string + err.string, PolyrunCliExitStatus.new(c == 0, c)]
    ensure
      Polyrun::Log.reset_io!
      merged_env.each_key do |k|
        if saved[k].nil?
          ENV.delete(k)
        else
          ENV[k] = saved[k]
        end
      end
    end
  end

  # Tests need a stable cwd; Dir.chdir is process-wide (acceptable in isolated examples).
  def with_chdir(dir, &block)
    Dir.chdir(dir, &block) # rubocop:disable ThreadSafety/DirChdir -- spec helper; callers use with_chdir
  end
end
