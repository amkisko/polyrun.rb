require "tempfile"

module Polyrun
  class CLI
    # No-subcommand default (`polyrun`) and path-only argv (implicit parallel run).
    module DefaultRun
      private

      def dispatch_default_parallel!(config_path)
        suite = Polyrun::Partition::Paths.detect_auto_suite(Dir.pwd)
        unless suite
          Polyrun::Log.warn "polyrun: no tests found (spec/**/*_spec.rb, test/**/*_test.rb, or Polyrun quick files). See polyrun help."
          return 2
        end

        Polyrun::Log.warn "polyrun: default → parallel #{suite} (use `polyrun help` for subcommands)" if @verbose

        case suite
        when :rspec
          cmd_start([], config_path)
        when :minitest
          cmd_parallel_minitest([], config_path)
        when :quick
          cmd_parallel_quick([], config_path)
        else
          2
        end
      end

      # If +argv[0]+ is in {IMPLICIT_PATH_EXCLUSION_TOKENS}, treat as a normal subcommand. Otherwise, path-like
      # tokens may trigger implicit parallel sharding (see +print_help+).
      def implicit_parallel_run?(argv)
        return false if argv.empty?
        return false if Polyrun::CLI::IMPLICIT_PATH_EXCLUSION_TOKENS.include?(argv[0])

        argv.any? { |a| cli_implicit_path_token?(a) }
      end

      def cli_implicit_path_token?(s)
        return false if s.start_with?("-") && s != "-"
        return true if s == "-"
        return true if s.start_with?("./", "../", "/")
        return true if s.end_with?(".rb")
        return true if File.exist?(File.expand_path(s))
        return true if /[*?\[]/.match?(s)

        false
      end

      def dispatch_implicit_parallel_targets!(argv, config_path)
        path_tokens = argv.select { |a| cli_implicit_path_token?(a) }
        head = argv.reject { |a| cli_implicit_path_token?(a) }
        expanded = expand_implicit_target_paths(path_tokens)
        if expanded.empty?
          Polyrun::Log.warn "polyrun: no files matched path arguments"
          return 2
        end

        suite = Polyrun::Partition::Paths.infer_suite_from_paths(expanded)
        if suite == :invalid
          Polyrun::Log.warn "polyrun: mixing _spec.rb and _test.rb paths in one run is not supported"
          return 2
        end
        if suite.nil?
          Polyrun::Log.warn "polyrun: could not infer suite from paths"
          return 2
        end

        tmp = Tempfile.new(["polyrun-paths-", ".txt"])
        begin
          tmp.write(expanded.join("\n") + "\n")
          tmp.close
          combined = head + ["--paths-file", tmp.path]
          case suite
          when :rspec
            cmd_start(combined, config_path)
          when :minitest
            cmd_parallel_minitest(combined, config_path)
          when :quick
            cmd_parallel_quick(combined, config_path)
          else
            2
          end
        ensure
          tmp.close! unless tmp.closed?
          begin
            File.unlink(tmp.path)
          rescue Errno::ENOENT
            # already removed
          end
        end
      end

      def expand_implicit_target_paths(path_tokens)
        path_tokens.flat_map do |p|
          abs = File.expand_path(p)
          if File.directory?(abs)
            spec = Dir.glob(File.join(abs, "**", "*_spec.rb")).sort
            test = Dir.glob(File.join(abs, "**", "*_test.rb")).sort
            quick = Dir.glob(File.join(abs, "**", "*.rb")).sort.reject do |f|
              File.basename(f).end_with?("_spec.rb", "_test.rb")
            end
            spec + test + quick
          elsif /[*?\[]/.match?(p)
            Dir.glob(abs).sort
          elsif File.file?(abs)
            [abs]
          else
            []
          end
        end.uniq
      end
    end
  end
end
