#!/usr/bin/env ruby
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "polyrun/quality/command"

module QualityPressure
  ROOT = File.expand_path("..", __dir__)
  BIN = File.join(ROOT, "bin/polyrun")
  SERIES = %w[wall_s cpu_s peak_rss_bytes storage_bytes graph_wall_s mutation_wall_s observe_wall_s].freeze

  module_function

  def stage_values(samples)
    SERIES.to_h do |key|
      values = samples.map { |sample| sample.fetch(key) }.sort
      [key, {"samples" => values, "median" => values[values.length / 2], "p95" => values[((values.length - 1) * 0.95).ceil], "max" => values.max}]
    end
  end

  def self_test
    samples = [1, 2, 3].map { |number| SERIES.each_with_index.to_h { |key, index| [key, (index + 1) * 100 + number] } }
    aggregate = stage_values(samples)
    expected = SERIES.each_with_index.to_h { |key, index| [key, (index + 1) * 100 + 2] }
    raise "mixed measurement series" unless aggregate.transform_values { |value| value["median"] } == expected
    expected_p95 = expected.transform_values { |value| value + 1 }
    raise "mixed p95 series" unless aggregate.transform_values { |value| value["p95"] } == expected_p95

    _, log, status = Open3.capture3("/usr/bin/time", *time_arguments, RbConfig.ruby, "-e", "sleep 0.03")
    raise "RSS meter unavailable" unless status.success? && peak_rss(log).positive?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    command = Polyrun::Quality::Command.call([RbConfig.ruby, "-e", "sleep 0.03"], root: ROOT, timeout: 3)
    aggregate_wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    raise "command wall mixed with aggregate" unless command["wall_s"].between?(0.03, aggregate_wall)

    {"pass" => true, "known_medians" => expected, "known_p95" => expected_p95, "direct_harness_peak_rss_bytes" => peak_rss(log),
     "direct_command_wall_s" => command["wall_s"], "direct_aggregate_wall_s" => aggregate_wall}
  end

  def time_arguments
    RUBY_PLATFORM.include?("darwin") ? ["-l"] : ["-f", "POLYRUN_PEAK_RSS_KIB=%M"]
  end

  def peak_rss(log)
    if RUBY_PLATFORM.include?("darwin")
      Integer(log.match(/^\s*(\d+)\s+maximum resident set size$/)[1])
    else
      Integer(log.match(/^POLYRUN_PEAK_RSS_KIB=(\d+)$/)[1]) * 1024
    end
  end

  def measure(load, samples)
    raise "samples must be >= 3 for a gateable run" if samples < 3

    rows = Array.new(samples) do
      output, log, status = Open3.capture3("/usr/bin/time", *time_arguments, RbConfig.ruby, __FILE__, "sample", load.to_s)
      raise "probe failed: #{output}\n#{log}" unless status.success?

      JSON.parse(output).merge("peak_rss_bytes" => peak_rss(log))
    end
    {"load" => load, "n" => samples, "series" => stage_values(rows), "raw" => rows,
     "network" => "not_in_scope", "memory_probe_class" => "process_lifetime",
     "propose_basis" => "max", "headroom" => 1.15}
  end

  def sample(load)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    before = Process.times
    stages = {}
    storage = 0
    Dir.mktmpdir("polyrun-quality-pressure") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      load.times do |index|
        File.write(File.join(root, "lib/fixture#{index}.rb"), "class Fixture#{index}; def value; helper; end; def helper; 1; end; end")
      end
      commands = {
        "graph_wall_s" => ["graph", "--enable", "index", "--json"],
        "mutation_wall_s" => ["mutate", "--enable", "--workers", "2", "--subject", "Fixture0#value", "--", RbConfig.ruby, "-Ilib", "-rfixture0", "-e", "abort unless Fixture0.new.value == 1"],
        "observe_wall_s" => ["observe", "--enable", "--output", File.join(root, "observed.json"), "--", RbConfig.ruby, "-Ilib", "-rfixture0", "-e", "#{load * 1000}.times { Fixture0.new.value }"]
      }
      commands.each do |name, arguments|
        result = Polyrun::Quality::Command.call([RbConfig.ruby, BIN, *arguments.take_while { |arg| arg != "--" }, "--root", root, *arguments.drop_while { |arg| arg != "--" }], root: root, timeout: 60, env: {"RUBYOPT" => nil})
        raise "#{name}: #{result.inspect}" unless result["exitstatus"].zero? && JSON.parse(result["stdout"])["ok"]

        stages[name] = result["wall_s"]
      end
      storage = Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sum { |path| File.size(path) }
    end
    after = Process.times
    stages.merge("wall_s" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
      "cpu_s" => after.utime + after.stime + after.cutime + after.cstime - before.utime - before.stime - before.cutime - before.cstime,
      "storage_bytes" => storage)
  end

  def run
    mode, argument = ARGV
    result = case mode
    when "self-test" then self_test
    when "sample" then sample(Integer(argument))
    when "measure", "propose", "gate"
      measured = measure(Integer(ENV.fetch("LOAD", "10")), Integer(ENV.fetch("SAMPLES", "3")))
      if mode == "propose"
        measured["ceilings"] = measured["series"].transform_values { |series| series["max"] * 1.15 }
      elsif mode == "gate"
        ceilings = JSON.parse(File.read(argument)).fetch("ceilings")
        measured["failures"] = ceilings.keys.select { |key| !measured["series"].key?(key) || measured["series"][key]["max"] > ceilings[key] }
        measured["pass"] = measured["failures"].empty?
      end
      measured
    else raise "usage: quality.rb self-test|measure|propose|gate CEILINGS"
    end
    puts JSON.pretty_generate(result)
    exit 1 if result["pass"] == false
  end
end

QualityPressure.run if $PROGRAM_NAME == __FILE__
