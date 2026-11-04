require "spec_helper"
require "benchmark"
require "fileutils"
require "tmpdir"

# Hot-path budget: Effective.build and Coverage::ConfigResolve.load are on CLI / suite start.
# rubocop:disable RSpec/DescribeClass, RSpec/NoExpectationExample
RSpec.describe "Config resolve benchmarks", :benchmark do
  let(:reps) { Integer(ENV.fetch("BENCH_CONFIG_REPS", "2000")) }

  it "measures Effective.build and Coverage::ConfigResolve.load", :aggregate_failures do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "polyrun.yml"), <<~YAML)
        version: 1
        workers: 6
        partition:
          paths_file: spec/list.txt
          shard_total: 8
          shard_index: 0
          strategy: round_robin
        prepare:
          recipe: shell
          env:
            PLAYWRIGHT_ENV: test
        coverage:
          minimum_line_percent: 80
          formats:
            - json
          output_path: coverage
      YAML
      File.write(File.join(dir, "config", "polyrun_coverage.yml"), <<~YAML)
        minimum_line_percent: 90
        track_under:
          - lib
          - app
      YAML

      cfg = Polyrun::Config.load(path: File.join(dir, "polyrun.yml"))
      env = {"POLYRUN_WORKERS" => "4", "POLYRUN_SHARD_TOTAL" => "8"}

      # Clear Effective per-thread cache between measured builds.
      effective_time = Benchmark.realtime do
        reps.times do
          Thread.current[:polyrun_effective_build] = {}
          Polyrun::Config::Effective.build(cfg, env: env)
        end
      end

      resolve_file_time = Benchmark.realtime do
        reps.times { Polyrun::Coverage::ConfigResolve.load(root: dir) }
      end

      FileUtils.rm_f(File.join(dir, "config", "polyrun_coverage.yml"))
      resolve_inline_time = Benchmark.realtime do
        reps.times { Polyrun::Coverage::ConfigResolve.load(root: dir) }
      end

      suite_raw = {
        "workers" => 5,
        "partition" => {
          "shard_total" => 8,
          "paths_build" => {"all_glob" => "spec/**/*_spec.rb", "stages" => []}
        },
        "suites" => {
          "unit" => {
            "workers" => 2,
            "partition" => {
              "shard_total" => 2,
              "paths_build" => {"all_glob" => "spec/unit/**/*_spec.rb"}
            }
          }
        }
      }
      suite_time = Benchmark.realtime do
        reps.times { Polyrun::Config::Suite.merge(suite_raw, "unit") }
      end

      BenchmarkProfile.log "\n  Config resolve (reps=#{reps}):"
      BenchmarkProfile.log "    Effective.build:              #{effective_time.round(4)}s (#{(effective_time / reps * 1000).round(3)}ms/op)"
      BenchmarkProfile.log "    ConfigResolve (file present): #{resolve_file_time.round(4)}s (#{(resolve_file_time / reps * 1000).round(3)}ms/op)"
      BenchmarkProfile.log "    ConfigResolve (inline only):  #{resolve_inline_time.round(4)}s (#{(resolve_inline_time / reps * 1000).round(3)}ms/op)"
      BenchmarkProfile.log "    Suite.merge:                  #{suite_time.round(4)}s (#{(suite_time / reps * 1000).round(3)}ms/op)"

      expect(effective_time).to be < 5.0
      expect(resolve_file_time).to be < 5.0
      expect(resolve_inline_time).to be < 5.0
      expect(suite_time).to be < 5.0
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/NoExpectationExample
