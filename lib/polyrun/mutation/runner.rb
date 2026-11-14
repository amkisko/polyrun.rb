require "tmpdir"
require_relative "../quality/command"
require_relative "../quality/sandbox"
require_relative "candidates"

module Polyrun
  module Mutation
    class Runner
      def initialize(root: Dir.pwd, workers: nil, timeout: nil, arguments: [], max_mutations: nil,
        max_report_bytes: nil, operators: nil, settings: {})
        overrides = {"workers" => workers, "timeout" => timeout, "max_mutations" => max_mutations, "max_report_bytes" => max_report_bytes}.compact
        @settings = Config::Tools.runtime("mutation", settings.merge(overrides))
        raise ArgumentError, "workers exceed configured maximum" if @settings["workers"] > @settings["max_workers"]

        @root, @workers, @timeout, @arguments = File.realpath(root), @settings["workers"], @settings["timeout"], arguments
        @max_mutations, @max_report_bytes = @settings["max_mutations"], @settings["max_report_bytes"]
        @operators = operators || Operators.select(@settings["operators"])
      end

      def call(subjects, shard: 1, total: 1)
        subjects = select_subjects(subjects, shard, total)
        return aggregate(subjects, [], nil) if subjects.empty?
        raise ArgumentError, "a test command is required after --" if @arguments.empty?

        mutations = Candidates.new(@root, operators: @operators, limit: @max_mutations, settings: @settings).call(subjects)
        raise ArgumentError, "no supported mutations for selected subjects" if mutations.empty?
        budget = {remaining: @max_report_bytes, mutex: Mutex.new}
        Dir.mktmpdir("polyrun-mutations") do |template|
          project = Quality::Sandbox.new(@root, settings: @settings["staging"])
          enforce_copy_budget!(project.bytes, mutations.size)

          project.copy_to(template)
          baseline = retain_result(execute(template, nil), budget)
          unless baseline["exitstatus"].zero? && baseline["code"] != "REPORT_LIMIT"
            return aggregate(subjects, [], baseline).merge("ok" => false, "code" => "BASELINE_FAILED", "killed" => nil, "survived" => nil)
          end
          results = parallel(mutations, template, budget)
          aggregate(subjects, results, baseline)
        end
      end

      private

      def enforce_copy_budget!(bytes, mutations)
        raise ArgumentError, "mutation copy budget exceeded; narrow subjects or raise max_copy_bytes" if bytes * (mutations + 2) > @settings["max_copy_bytes"]
      end

      def parallel(mutations, template, budget)
        pending = ::Queue.new
        results = Array.new(mutations.size)
        mutations.each_with_index { |mutation, index| pending << [mutation, index] }
        threads = Array.new([@workers, mutations.size].min) do
          Thread.new do # rubocop:disable ThreadSafety/NewThread -- bounded subprocess workers with isolated copies
            loop do
              mutation, index = pending.pop(true)
              result = execute(template, mutation)
              results[index] = retain_result(result, budget)
            rescue ThreadError
              break
            end
          end
        end
        threads.each(&:value)
        results
      ensure
        threads&.each { |thread| thread.kill if thread.alive? }
        threads&.each(&:join)
      end

      def execute(template, mutation)
        Dir.mktmpdir("polyrun-mutation") do |directory|
          project = Quality::Sandbox.new(template, settings: @settings["staging"])
          project.copy_to(directory)
          apply_mutation(directory, mutation) if mutation
          command = @arguments.map { |argument| argument.start_with?("#{@root}/") ? File.join(directory, argument.delete_prefix("#{@root}/")) : argument }
          result = Quality::Command.call(command, root: directory, timeout: @timeout, max_output: @settings["max_output_bytes"], env: Quality::Sandbox.environment(directory))
          result.merge!(mutation) if mutation
          result["code"] = {0 => mutation ? "SURVIVED" : "BASELINE_OK", 1 => mutation ? "KILLED" : "BASELINE_FAILED",
                            122 => "OUTPUT_LIMIT", 124 => "TIMEOUT", 127 => "COMMAND_UNAVAILABLE"}.fetch(result["exitstatus"], "COMMAND_FAILED")
          result
        end
      end

      def retain_result(result, budget)
        budget[:mutex].synchronize do
          size = result["stdout"].bytesize + result["stderr"].bytesize
          if size > budget[:remaining]
            result.merge!("stdout" => "", "stderr" => "", "code" => "REPORT_LIMIT")
          else
            budget[:remaining] -= size
          end
        end
        result
      end

      def apply_mutation(directory, mutation)
        file = File.join(directory, mutation["path"])
        source = File.binread(file)
        raise ArgumentError, "source changed before mutation testing" unless Digest::SHA256.hexdigest(source) == mutation["original_hash"]

        source[mutation["start"]...mutation["end"]] = mutation["replacement"].b
        File.binwrite(file, source)
      end

      def select_subjects(subjects, shard, total)
        unless shard.is_a?(Integer) && total.is_a?(Integer) && total.positive? && (1..total).cover?(shard)
          raise ArgumentError, "shard must be between 1 and total"
        end
        raise ArgumentError, "at least one subject is required" unless subjects.is_a?(Array) && !subjects.empty?
        raise ArgumentError, "too many mutation subjects" if subjects.size > @settings["max_subjects"]
        unless subjects.all? { |subject| valid_subject?(subject) }
          raise ArgumentError, "invalid mutation subject"
        end

        subjects.uniq.sort.each_with_index.filter_map { |subject, index| subject if index % total == shard - 1 }
      end

      def valid_subject?(subject)
        subject.is_a?(String) && !subject.empty? && !subject.start_with?("-") && !subject.match?(/[\s\x00]/)
      end

      def aggregate(subjects, results, baseline)
        complete = results.all? { |result| %w[KILLED SURVIVED].include?(result["code"]) }
        killed = complete ? results.count { |result| result["code"] == "KILLED" } : nil
        survived = complete ? results.count { |result| result["code"] == "SURVIVED" } : nil
        {"ok" => complete && survived.zero?, "engine" => "polyrun", "subjects" => subjects, "mutations" => results.size,
         "killed" => killed, "survived" => survived, "baseline" => baseline, "results" => results}
      end
    end
  end
end
