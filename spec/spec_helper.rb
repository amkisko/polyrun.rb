$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "tmpdir"

polyrun_cov_measure =
  ENV["POLYRUN_COVERAGE_DISABLE"] != "1" &&
  %w[1 true yes].include?(ENV["POLYRUN_COVERAGE"]&.to_s&.downcase)

# Stdlib Coverage must record lib/ after start; see Polyrun::Coverage::Collector.start!
# (skips Coverage.start when already running).
if polyrun_cov_measure
  require "coverage"
  branch = %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_BRANCHES"]&.downcase)
  ::Coverage.start(lines: true, branches: branch)
end

if polyrun_cov_measure
  require "polyrun/coverage/rails"
  Polyrun::Coverage::Rails.start!(root: File.expand_path("..", __dir__))
end

require "polyrun"
require_relative "support/polyrun_cli_helpers"

RSpec.configure do |config|
  # run-shards may set POLYRUN_SHARD_*; most examples assume a clean env. Collector keeps
  # shard_total_at_start from start! so clearing here does not break worker coverage gates.
  config.before do
    ENV.delete("POLYRUN_SHARD_INDEX")
    ENV.delete("POLYRUN_SHARD_TOTAL")
    ENV.delete("POLYRUN_SHARD_PROCESSES")
    # So partition shard_index/total resolve from YAML in tests, not the host CI runner.
    ENV.delete("CI_NODE_INDEX")
    ENV.delete("CI_NODE_TOTAL")
    ENV.delete("BUILDKITE_PARALLEL_JOB")
    ENV.delete("BUILDKITE_PARALLEL_JOB_COUNT")
    ENV.delete("CIRCLE_NODE_INDEX")
    ENV.delete("CIRCLE_NODE_TOTAL")
  end

  config.include PolyrunCliHelpers, file_path: %r{/spec/polyrun/}
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
end
