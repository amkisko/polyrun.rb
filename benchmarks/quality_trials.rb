#!/usr/bin/env ruby
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "time"
require "digest"
require "rbconfig"
require_relative "quality_observer_fixture"

# Replay measured alternatives in temporary source; gate the production recorder separately.

root = File.expand_path("..", __dir__)
templates = QualityObserverFixture.templates
source_template = templates.fetch(:source_template)
cache_original = templates.fetch(:cache_original)
cache_fetch = templates.fetch(:cache_fetch)
cache_direct = templates.fetch(:cache_direct)
original_count = templates.fetch(:original_count)
nested_count = templates.fetch(:nested_count)
flat_rows = templates.fetch(:flat_rows)
nested_rows = templates.fetch(:nested_rows)
base_command = File.read(File.join(root, "lib/polyrun/quality/command.rb")).sub(".clamp(0.0001, 0.001)", ".clamp(0.001, 0.02)")
abort "completion poll changed; update the trial fixture" unless base_command.include?(".clamp(0.001, 0.02)")
budget_path = File.join(root, "benchmarks/quality-ceilings.json")
ceilings = JSON.parse(File.read(budget_path)).fetch("ceilings")
original_ceilings = ceilings.dup
revision, = Open3.capture2("git", "rev-parse", "HEAD", chdir: root)
source = Dir.glob(File.join(root, "lib/**/*.rb")).sort.map { |path| path.delete_prefix("#{root}/") + "\0" + File.binread(path) }.join("\0")

episode = {"started_at" => Time.now.utc.iso8601, "accepted" => false, "repository_revision" => revision.strip, "production_source_sha256" => Digest::SHA256.hexdigest(source), "machine_class" => RUBY_PLATFORM, "ruby_version" => RUBY_VERSION, "iterations" => [], "binding" => "benchmarks/quality-binding.md", "ceilings_before" => original_ceilings, "ceilings_after" => ceilings, "network" => "not_in_scope", "memory_probe_class" => "process_lifetime", "propose_basis" => "max", "headroom" => 1.15}
Dir.mktmpdir("polyrun-pressure-variants") do |copy|
  FileUtils.cp_r(File.join(root, "lib"), copy)
  FileUtils.mkdir_p(File.join(copy, "bin"))
  FileUtils.cp(File.join(root, "bin/polyrun"), File.join(copy, "bin/polyrun"))
  FileUtils.mkdir_p(File.join(copy, "benchmarks"))
  FileUtils.cp(File.join(root, "benchmarks/quality.rb"), File.join(copy, "benchmarks/quality.rb"))
  hook = File.join(copy, "lib/polyrun/quality/observe_hook.rb")
  command = File.join(copy, "lib/polyrun/quality/command.rb")
  budget = File.join(copy, "benchmarks/quality-ceilings.json")
  File.write(budget, JSON.generate("ceilings" => ceilings))
  run = lambda do |mode, load|
    out, err, status = Open3.capture3({"LOAD" => load.to_s, "SAMPLES" => "3"}, RbConfig.ruby, File.join(copy, "benchmarks/quality.rb"), mode, budget)
    raise "probe failed: #{out}\n#{err}" unless status.success? || mode == "gate"
    JSON.parse(out)
  end
  File.write(hook, source_template)
  File.write(command, base_command)
  episode["calibration"] = run.call("self-test", 5)
  raise "calibration failed" unless episode["calibration"]["pass"]
  episode["baseline"] = run.call("measure", 5)
  episode["stress"] = run.call("measure", 50)
  initial_observation_ceiling = episode["stress"]["series"]["observe_wall_s"]["max"] * 1.15
  raise "observation ceiling must tighten the initial stress envelope" unless ceilings["observe_wall_s"] < initial_observation_ceiling

  episode["ceilings_before"]["observe_wall_s"] = initial_observation_ceiling
  episode["ratchet"] = {"primary_series" => "observe_wall_s", "basis" => "initial stress maximum times 1.15",
                        "before" => initial_observation_ceiling, "after" => ceilings["observe_wall_s"]}
  puts "calibration, baseline L0=5, stress L1=50 complete"
  $stdout.flush
  retained = source_template
  10.times do |index|
    number = index + 1
    candidate = retained.dup
    primary = "observe_wall_s"
    case number
    when 1
      candidate.sub!(cache_original, cache_fetch)
      change = "cache canonical paths"
    when 2
      candidate.sub!("event.method_id.to_s]", "event.method_id]")
      change = "delay method string conversion"
    when 3
      candidate.sub!("key = [path, event.defined_class.to_s, event.method_id]", "owner = owners.fetch(event.defined_class) { |value| text = value.to_s; owners[value] = text if owners.size < limit; text }; key = [path, owner, event.method_id]")
      change = "try bounded owner-name cache"
    when 4
      count = original_count.sub("event.method_id.to_s]", "event.method_id]")
      candidate.sub!(count, nested_count).sub!(flat_rows, nested_rows)
      change = "nested counters instead of tuple allocation"
    when 5
      candidate.sub!("next unless Process.pid == process", "")
      change = "check process ownership only when writing"
    when 6
      base_command = base_command.sub(".clamp(0.001, 0.02)", ".clamp(0.001, 0.005)")
      change = "completion poll 20ms to 5ms"
    when 7
      candidate.sub!("if methods&.key?(name)\nmethods[name] += 1", "count = methods && methods[name]\nif count\nmethods[name] = count + 1")
      change = "single counter lookup"
    when 8
      candidate.sub!("methods[name] = count + 1", "count[0] += 1").sub!("methods[name] = 1", "methods[name] = [1]").sub!('"count" => count}', '"count" => count[0]}')
      change = "try mutable counter cells"
    when 9
      candidate.sub!(cache_fetch, cache_direct)
      change = "direct positive and negative path-cache lookup"
    when 10
      base_command = base_command.sub(".clamp(0.001, 0.005)", ".clamp(0.0001, 0.001)")
      change = "completion poll 5ms to 1ms"
    end
    previous = episode["iterations"].last
    if previous && previous["prove"]["failures"].include?(previous["primary_series"])
      primary = previous["primary_series"]
    end
    raise "unchanged observer candidate #{number}" if candidate == retained && ![6, 10].include?(number)
    File.write(hook, candidate)
    File.write(command, base_command)
    measured = run.call("gate", 50)
    decision = [3, 8].include?(number) ? "rejected: extra state without an established gain" : "retained for the next temporary trial; production acceptance is separate"
    retained = candidate unless [3, 8].include?(number)
    episode["iterations"] << {"iteration" => number, "primary_series" => primary, "hypothesis" => change, "change" => change, "decision" => decision, "source_sha256" => Digest::SHA256.hexdigest(candidate + base_command), "prove" => measured}
    puts "cycle #{number}: #{primary} pass=#{measured["pass"]} failures=#{measured["failures"].inspect}"
    $stdout.flush
  end
end
output_path = ENV.fetch("QUALITY_EPISODE_OUTPUT", File.join(root, "benchmarks/output/quality-trials.json"))
production_output, production_error, production_status = Open3.capture3({"LOAD" => "50", "SAMPLES" => "3"}, RbConfig.ruby, File.join(root, "benchmarks/quality.rb"), "gate", budget_path)
episode["production_gate"] = JSON.parse(production_output)
episode["integration_prove"] = {"primary_series" => episode["iterations"].last["primary_series"],
                               "change" => "Use the complete production recorder after the temporary historical alternatives",
                               "prove" => episode["production_gate"]}
episode["accepted"] = production_status.success? && episode["production_gate"]["pass"] && episode["iterations"].size >= 10
episode["finished_at"] = Time.now.utc.iso8601
episode["notes"] = ["The strict episode repeats ten source-change experiments in an isolated checkout after complete calibration. No test suite ran concurrently. Other host activity is uncontrolled; no small comparative timing claim is made.", "Observer candidates preserve the fixture trace fields but are experimental historical alternatives, not replacements for the production recorder. Final production gets its own gate.", "Ceilings are read from the checked-in budget file and never changed by this script."]
FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(episode) + "\n")
puts JSON.generate("accepted" => episode["accepted"], "output" => output_path)
exit(episode["accepted"] ? 0 : 1)
