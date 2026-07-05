require "open3"
require "stringio"

module PolyrunCliHelpers
  PolyrunCliExitStatus = Struct.new(:ok, :exitstatus) do
    def success?
      ok
    end
  end
  # Commands that call Kernel.exec when hooks are empty; in-process polyrun would replace the RSpec worker.
  POLYRUN_EXEC_CLI_SUBCOMMANDS = %w[ci-shard-run ci-shard-rspec].freeze

  def polyrun_cli_subcommand(*args)
    argv = args.map(&:to_s)
    return argv.first if argv.empty?

    if argv.first == "-c" && argv.size >= 3
      argv[2]
    else
      argv.first
    end
  end

  # When POLYRUN_COVERAGE=1, run the CLI in-process so stdlib Coverage attributes
  # hits to lib/polyrun/cli/*.rb (subprocess tests do not). Set POLYRUN_CLI_SUBPROCESS=1
  # to force bin/polyrun (e.g. debugging).
  def polyrun(*args, in_process: nil, env: nil)
    root = File.expand_path("../..", __dir__)
    bin = File.join(root, "bin", "polyrun")
    merged = {"RUBYOPT" => nil}.merge(env || {})
    subcommand = polyrun_cli_subcommand(*args)
    use_ip = if !in_process.nil?
      in_process
    else
      ENV["POLYRUN_COVERAGE"] == "1" &&
        ENV["POLYRUN_CLI_SUBPROCESS"] != "1" &&
        !POLYRUN_EXEC_CLI_SUBCOMMANDS.include?(subcommand)
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
  def parse_polyrun_json(out)
    text = out.to_s.dup
    text = text.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
    unless text.valid_encoding?
      text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    line = text.lines.map(&:strip).find { |l| l.start_with?("{") }
    raise "no JSON in polyrun output: #{out.inspect}" unless line

    JSON.parse(line)
  end

  def with_chdir(dir, &block)
    Dir.chdir(dir, &block) # rubocop:disable ThreadSafety/DirChdir -- spec helper; callers use with_chdir
  end
end
