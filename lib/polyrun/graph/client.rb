require "fileutils"
require_relative "plan"
require_relative "../quality/command"
require "rbconfig"
require_relative "../quality/sandbox"

module Polyrun
  module Graph
    class Client
      def initialize(root: Dir.pwd, timeout: nil, settings: {})
        @settings = Config::Tools.runtime("graph", settings.merge(timeout ? {"timeout" => timeout} : {}))
        @root = File.realpath(root)
        library = File.expand_path("../..", __dir__)
        @command = [RbConfig.ruby, "-I", library, "-rpolyrun/graph/worker", "-e", "exit Polyrun::Graph::Worker.run(ARGV)", "--"]
        @timeout = @settings["timeout"]
      end

      def call(arguments, prove: [])
        state = Workspace.new(@root, settings: @settings).path(@settings["state_dir"])

        FileUtils.mkdir_p(state)
        lock_path = File.join(state, "polyrun.lock")
        raise Error.new("INVALID_PLAN", "symbolic link in lock path") if File.symlink?(lock_path)

        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          raise Error.new("WORKSPACE_BUSY", "another graph command is running") unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          dispatch(arguments, prove)
        end
      end

      private

      def dispatch(arguments, prove)
        verb, id = arguments.reject { |argument| argument == "--json" }
        return check(Plan.new(@root, id, settings: @settings), arguments, prove) if verb == "check"

        invoke(arguments)
      end

      def invoke(arguments)
        Quality::Command.call(@command + arguments, root: @root, timeout: @timeout, max_output: @settings["max_output_bytes"], env: {"POLYRUN_GRAPH_ROOT" => @root, "POLYRUN_GRAPH_SETTINGS" => JSON.generate(@settings), "RUBYOPT" => nil})
      end

      def check(plan, arguments, prove)
        checked = false
        plan.invalidate!
        result = invoke(arguments)
        return result unless result["exitstatus"].zero?

        plan.record_check!
        prove_result = prove.empty? ? nil : Quality::Command.call(prove, root: plan.tree, timeout: @timeout, max_output: @settings["max_output_bytes"], env: Quality::Sandbox.environment(plan.tree))
        if prove_result && !prove_result["exitstatus"].zero?
          raise Error.new("PROVE_FAILED", "prove command failed: #{prove_result["stderr"]}", exitstatus: prove_result["exitstatus"])
        end
        plan.verify!
        checked = true
        result
      ensure
        plan.invalidate! unless checked
      end
    end
  end
end
