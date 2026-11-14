require "spec_helper"
require "rubygems/package"
require "json"
require "fileutils"

RSpec.describe "standalone Polyrun package" do
  it "indexes, edits, and mutation-tests from only the packaged files and Ruby" do
    Dir.mktmpdir do |directory|
      package_path = File.join(directory, "polyrun.gem")
      specification = Gem::Specification.load(File.expand_path("../../../polyrun.gemspec", __dir__))
      Gem::Package.build(specification, true, false, package_path)
      installation = File.join(directory, "installation")
      Gem::Package.new(package_path).extract_files(installation)
      project = File.join(directory, "project")
      FileUtils.mkdir_p(File.join(project, "lib"))
      File.write(File.join(project, "lib/account.rb"), "class Account; def self.value; first; end; def self.first; 1; end; def self.second; 2; end; end")
      File.write(File.join(project, "probe.rb"), "require 'account'; abort unless Account.value == 2")
      binary = File.join(installation, "bin/polyrun")
      env = {"RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil, "PATH" => File.dirname(Gem.ruby)}
      output, status = Open3.capture2e(env, Gem.ruby, binary, "graph", "--enable", "index", "--json", chdir: project)
      expect(status.exitstatus).to eq(0), output
      expect(JSON.parse(output)["nodes"]).to be > 0
      index = JSON.parse(output)
      graph = lambda do |*arguments|
        result, command_status = Open3.capture2e(env, Gem.ruby, binary, "graph", "--enable", *arguments, "--json", chdir: project)
        expect(command_status.exitstatus).to eq(0), result
        JSON.parse(result)
      end
      node = graph.call("inspect", "Account.value", "--calls").fetch("nodes").first.fetch("calls").find { |call| call["name"] == "first" }
      change = {"snapshot" => index.fetch("snapshot"), "operations" => [{"op" => "replace_call_name", "node" => node.fetch("id"), "expect" => node.slice("name", "fingerprint"), "replacement" => "second"}]}
      File.write(File.join(project, "change.json"), JSON.generate(change))
      plan = graph.call("plan", "change.json").fetch("plan_id")
      graph.call("check", plan)
      graph.call("apply", plan)
      output, status = Open3.capture2e(env, Gem.ruby, "-Ilib", "probe.rb", chdir: project)
      expect(status.exitstatus).to eq(0), output
      output, status = Open3.capture2e(env, Gem.ruby, binary, "mutate", "--enable", "--subject", "Account.value", "--", Gem.ruby, "-Ilib", "probe.rb", chdir: project)
      expect(status.exitstatus).to eq(0), output
      expect(JSON.parse(output)).to include("engine" => "polyrun", "survived" => 0)
    end
  end
end
