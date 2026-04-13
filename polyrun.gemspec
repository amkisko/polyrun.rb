require_relative "lib/polyrun/version"

Gem::Specification.new do |spec|
  spec.name = "polyrun"
  spec.version = Polyrun::VERSION
  spec.authors = ["Andrei Makarov"]
  spec.email = ["contact@kiskolabs.com"]
  spec.summary = "Parallel tests, coverage (SimpleCov-compatible) formatters, fixtures/snapshots, assets & DB provisioning—zero runtime deps"
  spec.homepage = "https://github.com/amkisko/polyrun.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*", "sig/**/*.rbs", "bin/polyrun", "README.md", "docs/SETUP_PROFILE.md", "LICENSE", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md", "polyrun.gemspec"].reject { |f| File.directory?(f) }
  spec.bindir = "bin"
  spec.executables = ["polyrun"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "#{spec.homepage}#readme",
    "rubygems_mfa_required" => "true"
  }

  # Normative: zero runtime dependencies (stdlib + vendored/native code only).
  # Ruby 3.5+: `benchmark` is no longer a default gem; keep scripts and `rake bench_merge` warning-free.
  spec.add_development_dependency "benchmark", ">= 0.3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "appraisal", "~> 2.5"
  spec.add_development_dependency "standard", "~> 1.52"
  spec.add_development_dependency "standard-custom", "~> 1.0"
  spec.add_development_dependency "standard-performance", "~> 1.8"
  spec.add_development_dependency "rubocop-rspec", "~> 3.8"
  spec.add_development_dependency "rubocop-thread_safety", "~> 0.7"
  spec.add_development_dependency "rbs", ">= 3.5"
end
