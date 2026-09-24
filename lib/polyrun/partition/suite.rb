module Polyrun
  module Partition
    # Chooses the parallel runner suite for bare +polyrun+ and validates command vs path lists.
    module Suite
      module_function

      # Resolve suite for default CLI dispatch.
      # Order: explicit +partition.suite+ (not auto) → infer from +paths_file+ → +detect_auto_suite+.
      # Returns +{ suite: :rspec|:minitest|:quick }+ or +{ error: "..." }+.
      def resolve_default(cwd: Dir.pwd, partition: {})
        configured = configured_suite(partition)
        return {error: "unknown partition.suite: #{configured.inspect} (expected auto, rspec, minitest, quick)"} unless
          %w[auto rspec minitest quick].include?(configured)

        inferred = infer_from_paths_file(cwd, partition)
        return inferred if inferred.is_a?(Hash) && inferred[:error]

        if configured != "auto"
          suite = configured.to_sym
          if inferred && inferred != suite
            return {
              error: "partition.suite is #{suite} but paths_file infers #{inferred} " \
                     "(fix partition.suite or the paths file)"
            }
          end
          return {suite: suite}
        end

        return {suite: inferred} if inferred

        auto = Paths.detect_auto_suite(cwd)
        return {suite: auto} if auto

        {
          error: "no tests found (spec/**/*_spec.rb, test/**/*_test.rb, or Polyrun quick files). See polyrun help."
        }
      end

      def infer_from_command(cmd)
        tokens = Array(cmd).map(&:to_s)
        return nil if tokens.empty?

        return :rspec if tokens.any? { |t| File.basename(t) == "rspec" }
        return :quick if tokens.include?("quick") && tokens.any? { |t| File.basename(t).include?("polyrun") }
        return :minitest if minitest_command?(tokens)

        nil
      end

      def command_mismatch_message(items, cmd)
        path_suite = Paths.infer_suite_from_paths(Array(items))
        cmd_suite = infer_from_command(cmd)

        if path_suite == :invalid
          return nil unless cmd_suite

          return "mixing _spec.rb and _test.rb paths is not supported with a #{cmd_suite} command " \
                 "(use a suite-agnostic custom command, or split the path list)"
        end

        return nil if path_suite.nil?
        return nil if cmd_suite.nil?
        return nil if path_suite == cmd_suite

        "paths infer #{path_suite} but command looks like #{cmd_suite} " \
          "(use parallel-#{path_suite}, fix partition.paths_file, or pass a matching command after --)"
      end

      def configured_suite(partition)
        suite = (partition["suite"] || partition[:suite] || "auto").to_s.downcase
        suite.empty? ? "auto" : suite
      end
      private_class_method :configured_suite

      def infer_from_paths_file(cwd, partition)
        paths_file = partition["paths_file"] || partition[:paths_file]
        return nil unless paths_file

        abs = File.expand_path(paths_file.to_s, cwd)
        return nil unless File.file?(abs)

        items = Paths.read_lines(abs)
        inferred = Paths.infer_suite_from_paths(items)
        return {error: "paths_file mixes _spec.rb and _test.rb (not supported in one run)"} if inferred == :invalid

        inferred
      end
      private_class_method :infer_from_paths_file

      def minitest_command?(tokens)
        return true if tokens.any? { |t| File.basename(t) == "rails" } && tokens.include?("test")
        return true if ruby_with_test_load_path?(tokens)

        false
      end
      private_class_method :minitest_command?

      def ruby_with_test_load_path?(tokens)
        tokens.each_with_index do |tok, i|
          next unless File.basename(tok) == "ruby"

          rest = tokens[(i + 1)..] || []
          rest.each_with_index do |arg, j|
            return true if arg == "-Itest"
            return true if arg == "-I" && rest[j + 1] == "test"
            next unless arg.start_with?("-I") && arg.length > 2

            return true if arg[2..].split(/[=:]/).include?("test")
          end
        end
        false
      end
      private_class_method :ruby_with_test_load_path?
    end
  end
end
