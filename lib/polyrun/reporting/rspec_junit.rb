require "fileutils"

module Polyrun
  module Reporting
    # CI: emit JUnit XML from RSpec's JSON formatter output (replaces +rspec_junit_formatter+).
    #
    #   require "polyrun/reporting/rspec_junit"
    #   Polyrun::Reporting::RspecJunit.install!(only_if: -> { ENV["CI"] })
    #
    # Ensure +.rspec+ or CLI keeps a human formatter (e.g. documentation) in addition to JSON.
    module RspecJunit
      module_function

      def install!(json_path: "rspec.json", junit_path: "coverage/junit-coverage.xml", only_if: nil)
        pred = only_if || -> { ENV["CI"] }
        return unless pred.call

        json_abs = File.expand_path(json_path)
        FileUtils.mkdir_p(File.dirname(json_abs))

        require "rspec/core"
        require "rspec/core/formatters/json_formatter"

        RSpec.configure do |config|
          config.add_formatter RSpec::Core::Formatters::JsonFormatter, json_abs
        end

        at_exit do
          next unless pred.call

          FileUtils.mkdir_p(File.dirname(File.expand_path(junit_path)))
          if File.file?(json_abs)
            Junit.write_from_json_file(json_abs, output_path: junit_path)
          end
        end
      end
    end
  end
end
