require "polyrun/benchmark/profile"
require "polyrun/benchmark/report"

# Test-suite adapter: performance specs use repo root for profile paths.
module BenchmarkProfile
  module_function

  def reset!
    Polyrun::Benchmark::Profile.reset!
  end

  def log(message = "")
    Polyrun::Benchmark::Profile.log(message)
  end

  def write!(repository_root: default_repository_root)
    Polyrun::Benchmark::Profile.write!(repository_root: repository_root)
  end

  def output_path(repository_root: default_repository_root, **kwargs)
    Polyrun::Benchmark::Profile.output_path(repository_root: repository_root, **kwargs)
  end

  def verbose?
    Polyrun::Benchmark::Profile.verbose?
  end

  def commit_sha(repository_root: default_repository_root)
    Polyrun::Benchmark::Profile.commit_sha(repository_root: repository_root)
  end

  def working_tree_clean?(repository_root: default_repository_root)
    Polyrun::Benchmark::Profile.working_tree_clean?(repository_root: repository_root)
  end

  def timestamp
    Polyrun::Benchmark::Profile.timestamp
  end

  def profile_header(repository_root: default_repository_root)
    Polyrun::Benchmark::Profile.profile_header(
      Polyrun::Benchmark::Profile.profile_meta(repository_root: repository_root)
    )
  end

  def default_repository_root
    File.expand_path("../..", __dir__)
  end
end
