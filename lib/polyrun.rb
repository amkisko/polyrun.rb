require_relative "polyrun/version"
require_relative "polyrun/log"
require_relative "polyrun/debug"
require_relative "polyrun/config"
require_relative "polyrun/coverage/merge"
require_relative "polyrun/coverage/filter"
require_relative "polyrun/coverage/result"
require_relative "polyrun/coverage/formatter"
require_relative "polyrun/coverage/collector"
require_relative "polyrun/coverage/reporting"
require_relative "polyrun/coverage/rails"
require_relative "polyrun/partition/plan"
require_relative "polyrun/partition/paths"
require_relative "polyrun/partition/paths_build"
require_relative "polyrun/queue/file_store"
require_relative "polyrun/data/fixtures"
require_relative "polyrun/data/cached_fixtures"
require_relative "polyrun/data/parallel_provisioning"
require_relative "polyrun/data/factory_instrumentation"
require_relative "polyrun/data/snapshot"
require_relative "polyrun/data/factory_counts"
require_relative "polyrun/prepare/assets"
require_relative "polyrun/prepare/artifacts"
require_relative "polyrun/database/shard"
require_relative "polyrun/database/url_builder"
require_relative "polyrun/database/provision"
require_relative "polyrun/database/clone_shards"
require_relative "polyrun/env/ci"
require_relative "polyrun/timing/merge"
require_relative "polyrun/timing/summary"
require_relative "polyrun/reporting/junit"
# RSpec JSON formatter + JUnit is opt-in: require "polyrun/reporting/rspec_junit" (loads RSpec only inside RspecJunit.install!).
require_relative "polyrun/cli"

if defined?(Rails::Railtie)
  require_relative "polyrun/railtie"
end

module Polyrun
  class Error < StandardError; end

  # Delegate to {Polyrun::Log} for swappable stderr/stdout (CLI and library messages).
  def self.stderr=(io)
    Log.stderr = io
  end

  def self.stderr
    Log.stderr
  end

  def self.stdout=(io)
    Log.stdout = io
  end

  def self.stdout
    Log.stdout
  end
end
