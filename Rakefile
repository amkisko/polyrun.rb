require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = %w[--parallel]
end

desc "Validate RBS signatures under sig/"
task :rbs do
  sh "bundle exec rbs -I sig validate"
end

task default: :spec
task ci: %i[spec rubocop]

desc "Compile and verify polyrun_coverage_merge native extension"
task :native_extension do
  sh "make native-extension"
end

namespace :coverage do
  desc "Run RSpec with Polyrun coverage (single process; gate from config/polyrun_coverage.yml)"
  task :rspec do
    sh({"POLYRUN_COVERAGE" => "1"}, *%w[bundle exec rspec])
  end

  desc "Run RSpec in parallel shards via polyrun, then merge coverage (gate from config/polyrun_coverage.yml)"
  task :parallel do
    env = {
      "POLYRUN_COVERAGE" => "1",
      "POLYRUN_MERGE_FORMATS" => "json,console"
    }
    workers = Integer(ENV.fetch("POLYRUN_COVERAGE_WORKERS", "4"), exception: false) || 4
    cmd = %W[bundle exec polyrun run-shards --workers #{workers} --merge-coverage --merge-format json,console -- bundle exec rspec]
    sh(env, *cmd)
  end
end

desc "Run coverage merge benchmark (see benchmark/merge_coverage.rb for MERGE_FILES, MERGE_LINES, MERGE_REPS, …)"
task :bench_merge do
  ruby = Gem.ruby
  script = File.expand_path("benchmark/merge_coverage.rb", __dir__)
  exec(ruby, script)
end

desc "Run RSpec performance benchmarks (writes tmp/benchmarks/profile_<sha>.log)"
task :bench_performance do
  sh({"BENCH_FILES" => ENV.fetch("BENCH_FILES", "110"),
      "BENCH_LINES" => ENV.fetch("BENCH_LINES", "310"),
      "BENCH_FRAGMENTS" => ENV.fetch("BENCH_FRAGMENTS", "8"),
      "BENCH_MERGE_REPS" => ENV.fetch("BENCH_MERGE_REPS", "3"),
      "BENCH_LINE_COUNT_REPS" => ENV.fetch("BENCH_LINE_COUNT_REPS", "5"),
      "BENCH_PEEK_REPS" => ENV.fetch("BENCH_PEEK_REPS", "200")},
    "bundle exec rspec spec/performance/benchmark_spec.rb spec/performance/benchmark_merge_spec.rb --tag benchmark")
end
