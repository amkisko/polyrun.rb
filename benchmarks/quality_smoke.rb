#!/usr/bin/env ruby
require "json"
require "tmpdir"
require "fileutils"
require "rbconfig"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "polyrun/quality/command"

bin = File.expand_path("../bin/polyrun", __dir__)
results = []
Dir.mktmpdir("polyrun-quality-smoke") do |root|
  FileUtils.mkdir_p(File.join(root, "lib"))
  File.write(File.join(root, "lib/account.rb"), "class Account; def value; helper; end; def helper; 1; end; def replacement; 2; end; end")
  graph = lambda do |*arguments|
    result = Polyrun::Quality::Command.call([RbConfig.ruby, bin, "graph", "--enable", *arguments, "--root", root, "--json"], root: root, timeout: 30)
    raise result.inspect unless result["exitstatus"].zero?

    JSON.parse(result["stdout"])
  end
  index = graph.call("index")
  node = graph.call("inspect", "Account#value", "--calls").fetch("nodes").first.fetch("calls").find { |call| call["name"] == "helper" }
  change = {"snapshot" => index.fetch("snapshot"), "operations" => [{"op" => "replace_call_name", "node" => node.fetch("id"), "expect" => node.slice("name", "fingerprint"), "replacement" => "replacement"}]}
  File.write(File.join(root, "change.json"), JSON.generate(change))
  plan = graph.call("plan", "change.json").fetch("plan_id")
  result = Polyrun::Quality::Command.call([RbConfig.ruby, bin, "graph", "--enable", "check", plan, "--root", root, "--json", "--prove", "--", RbConfig.ruby, "-Ilib", "-raccount", "-e", "abort unless Account.new.value == 2"], root: root, timeout: 30)
  raise result.inspect unless result["exitstatus"].zero?

  graph.call("apply", plan)
  results << {"scenario" => "polyrun_graph_edit", "pass" => true}
  File.write(File.join(root, "probe.rb"), "require 'account'; abort unless Account.new.value == 2")
  result = Polyrun::Quality::Command.call([RbConfig.ruby, bin, "mutate", "--enable", "--root", root, "--subject", "Account#value", "--workers", "2", "--", RbConfig.ruby, "-Ilib", "probe.rb"], root: root, timeout: 30)
  report = JSON.parse(result["stdout"])
  results << {"scenario" => "polyrun_mutation_testing", "totals" => report.slice("ok", "mutations", "killed", "survived")}
  raise JSON.pretty_generate(results) unless result["exitstatus"].zero? && report["killed"].positive?
end
puts JSON.pretty_generate(results)
