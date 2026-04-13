$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "polyrun"
require_relative "support/polyrun_cli_helpers"

RSpec.configure do |config|
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
