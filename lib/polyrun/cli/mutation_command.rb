require "json"
require_relative "../graph/error"

module Polyrun
  class CLI
    module MutationCommand
      private

      def cmd_mutate(argv)
        options = {}
        command = extract_tool_command!(argv)
        parse_mutation_options!(argv, options)
        settings = configured_tool("mutation", options)
        require_relative "../mutation/runner"
        subjects = mutation_subjects(settings)
        report = Mutation::Runner.new(root: settings["root"], settings: settings,
          arguments: command || settings["command"]).call(subjects, shard: settings["shard"], total: settings["total"])
        payload = JSON.generate(report)
        File.write(settings["output"], payload + "\n") if settings["output"]
        Polyrun::Log.puts payload
        report["ok"] ? 0 : 1
      rescue OptionParser::ParseError, ArgumentError, KeyError, JSON::ParserError, SystemCallError, Graph::Error, Psych::Exception => e
        Polyrun::Log.warn "mutate: #{e.message}"
        2
      end

      def parse_mutation_options!(argv, options)
        parser = OptionParser.new do |opts|
          common_tool_options(opts, options)
          %w[max-mutations workers shard total].each do |key|
            opts.on("--#{key} N", Integer) { |value| options[key.tr("-", "_").to_sym] = value }
          end
          %w[subjects-file plan output].each do |key|
            opts.on("--#{key} PATH") { |value| options[key.tr("-", "_").to_sym] = value }
          end
          opts.on("--subject EXPRESSION") { |value| (options[:subjects] ||= []) << value }
          opts.on("--observed PATH") { |value| (options[:observed] ||= []) << value }
        end
        raise ArgumentError, "unexpected mutation arguments" unless parser.parse(argv).empty?
      end

      def mutation_file_subjects(settings)
        path = File.expand_path(settings["subjects_file"], settings["root"])
        raise ArgumentError, "subjects file is too large" if File.size(path) > settings["max_input_bytes"]

        File.readlines(path, chomp: true).reject(&:empty?)
      end

      def mutation_graph_settings(root)
        cfg = Config.load(path: ENV["POLYRUN_CONFIG"], root: root)
        Config::Tools.resolve(cfg, "graph", root: root)
      end

      def mutation_subjects(settings)
        subjects = settings["subjects"].dup
        subjects.concat(mutation_file_subjects(settings)) if settings["subjects_file"]
        if settings["plan"] || !settings["observed"].empty?
          require_relative "../mutation/subjects"
          graph = mutation_graph_settings(settings["root"])
          subjects.concat(Mutation::Subjects.from_plan(settings["root"], settings["plan"], settings: graph)) if settings["plan"]
          settings["observed"].each { |path| subjects.concat(Mutation::Subjects.from_observation(File.expand_path(path, settings["root"]), max_bytes: settings["max_artifact_bytes"])) }
        end
        subjects
      end
    end
  end
end
