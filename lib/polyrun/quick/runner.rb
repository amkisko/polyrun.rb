require "pathname"

require_relative "assertions"
require_relative "errors"
require_relative "example_group"
require_relative "example_runner"
require_relative "reporter"

module Polyrun
  # Micro test runner: nested +describe+, +it+ / +test+, +before+ / +after+, +let+ / +let!+,
  # +expect().to+ matchers, optional +Polyrun::Quick.capybara!+ when the +capybara+ gem is loaded.
  #
  # Run: +polyrun quick+ or +polyrun quick spec/foo.rb+
  #
  # Coverage: when +POLYRUN_COVERAGE=1+ or (+config/polyrun_coverage.yml+ and +POLYRUN_QUICK_COVERAGE=1+), starts
  # {Polyrun::Coverage::Rails} before loading quick files so stdlib +Coverage+ records them.
  module Quick
    module DSL
      def describe(name, &block)
        Quick.describe(name, &block)
      end
    end

    class Collector
      attr_reader :groups

      def initialize
        @groups = []
      end

      def register(group)
        @groups << group
      end
    end

    # rubocop:disable ThreadSafety/ClassAndModuleAttributes, ThreadSafety/ClassInstanceVariable
    class << self
      attr_accessor :collector

      def capybara!
        @capybara_enabled = true
      end

      def capybara?
        @capybara_enabled == true
      end

      def reset_capybara_flag!
        @capybara_enabled = false
      end

      def describe(name, &block)
        group = ExampleGroup.new(name)
        group.instance_eval(&block) if block
        (collector || raise(Error, "Polyrun::Quick.describe used outside polyrun quick")).register(group)
      end
    end
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes, ThreadSafety/ClassInstanceVariable

    class Runner
      def self.run(paths:, out: $stdout, err: $stderr, verbose: false)
        new(out: out, err: err, verbose: verbose).run(paths)
      end

      def initialize(out: $stdout, err: $stderr, verbose: false)
        @out = out
        @err = err
        @verbose = verbose
      end

      def run(paths)
        Quick.reset_capybara_flag!

        files = expand_paths(paths)
        if files.empty?
          Polyrun::Log.warn "polyrun quick: no files (pass paths or add Quick files under spec/ or test/, e.g. spec/polyrun_quick/**/*.rb or spec/**/*.rb excluding *_spec.rb / *_test.rb)"
          return 2
        end

        quick_start_coverage_if_configured!

        collector = load_quick_files!(files)
        return 1 unless collector

        reporter = Reporter.new(@out, @err, @verbose)
        run_examples!(collector, reporter)
        reporter.summary
      ensure
        Quick.collector = nil
        Quick.reset_capybara_flag!
      end

      def load_quick_files!(files)
        collector = Collector.new
        Quick.collector = collector

        files.each do |path|
          code = File.read(path)
          loader = Object.new
          loader.extend(DSL)
          loader.instance_eval(code, path, 1)
        rescue SyntaxError, StandardError => e
          Polyrun::Log.warn "polyrun quick: failed to load #{path}: #{e.class}: #{e.message}"
          Quick.collector = nil
          return nil
        end

        Quick.collector = nil
        collector
      end

      def run_examples!(collector, reporter)
        collector.groups.each do |root|
          root.each_example_with_ancestors do |chain, desc, block|
            inner = chain.last
            example_runner = ExampleRunner.new(reporter)
            example_runner.run(
              group_name: inner.full_name,
              description: desc,
              ancestor_chain: chain,
              block: block
            )
          end
        end
      end

      def quick_start_coverage_if_configured!
        return unless Polyrun::Coverage::Collector.coverage_requested_for_quick?(Dir.pwd)
        return if Polyrun::Coverage::Collector.started?

        require_relative "../coverage/rails"
        Polyrun::Coverage::Rails.start!(
          root: File.expand_path(Dir.pwd),
          meta: {"command_name" => "polyrun quick"}
        )
      end

      def expand_paths(paths)
        return default_globs if paths.nil? || paths.empty?

        paths.flat_map do |p|
          expanded = File.expand_path(p)
          if File.directory?(expanded)
            Dir.glob(File.join(expanded, "**", "*.rb")).sort
          elsif /[*?\[]/.match?(p)
            Dir.glob(File.expand_path(p)).sort
          elsif File.file?(expanded)
            [expanded]
          else
            []
          end
        end.uniq
      end

      def default_globs
        base = File.expand_path(Dir.pwd)
        globs = [
          File.join(base, "spec", "polyrun_quick", "**", "*.rb"),
          File.join(base, "test", "polyrun_quick", "**", "*.rb"),
          File.join(base, "spec", "**", "*.rb"),
          File.join(base, "test", "**", "*.rb")
        ]
        globs.flat_map { |g| Dir.glob(g) }.uniq.reject { |p| default_quick_exclude?(p, base) }.sort
      end

      # Omit RSpec/Minitest files and common helpers so +polyrun quick+ with no args does not load normal suites.
      def default_quick_exclude?(path, base)
        rel = Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
        parts = rel.split(File::SEPARATOR)
        bn = File.basename(path)
        return true if bn.end_with?("_spec.rb", "_test.rb")
        return true if %w[spec_helper.rb rails_helper.rb test_helper.rb].include?(bn)
        return true if parts[0] == "spec" && %w[support fixtures factories].include?(parts[1])
        return true if parts[0] == "test" && %w[support fixtures].include?(parts[1])

        false
      end
    end
  end
end
