require "json"
require "tmpdir"
require_relative "command"

module Polyrun
  module Quality
    module Observe
      module_function

      def call(command, root:, output:, timeout: 300, limit: 10_000, max_output: Command::DEFAULT_OUTPUT_LIMIT, max_artifact_bytes: 16_777_216)
        raise ArgumentError, "max entries must be positive" unless limit.is_a?(Integer) && limit.positive?

        output = File.expand_path(output)
        Dir.mktmpdir("polyrun-observe", File.dirname(output)) do |directory|
          artifact = File.join(directory, "trace.json")
          result = Command.call(command, root: root, timeout: timeout, max_output: max_output, env: environment(root, artifact, limit))
          present = File.file?(artifact)
          if present
            validate_artifact!(artifact, max_artifact_bytes)
            File.rename(artifact, output)
          end
          result["ok"] = result["exitstatus"].zero? && present
          result["code"] = if !result["exitstatus"].zero?
            "COMMAND_FAILED"
          elsif present
            "OBSERVED"
          else
            "TRACE_MISSING"
          end
          result
        end
      end

      def environment(root, artifact, limit)
        library = File.expand_path("../..", __dir__)
        {"POLYRUN_OBSERVE_ROOT" => File.realpath(root), "POLYRUN_OBSERVE_OUTPUT" => artifact,
         "POLYRUN_OBSERVE_LIMIT" => limit.to_s, "POLYRUN_OBSERVE_RUBYOPT" => ENV["RUBYOPT"],
         "RUBYLIB" => [library, ENV["RUBYLIB"]].compact.join(File::PATH_SEPARATOR),
         "RUBYOPT" => "#{ENV["RUBYOPT"]} -rpolyrun/quality/observe_hook"}
      end

      def validate_artifact!(path, max_bytes)
        raise ArgumentError, "observation artifact is too large" if File.size(path) > max_bytes

        trace = JSON.parse(File.read(path))
        unless trace.is_a?(Hash) && trace["calls"].is_a?(Array) && trace["provenance"] == "observed"
          raise ArgumentError, "invalid observation artifact"
        end
      end
      private_class_method :environment, :validate_artifact!
    end
  end
end
