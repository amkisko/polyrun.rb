require "spec_helper"
require "polyrun/graph/index"
require "polyrun/graph/inspect"
require "polyrun/graph/planner"
require "fileutils"

RSpec.describe Polyrun::Graph::Index do
  it "keeps instance and singleton dispatch separate and reports control signals" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "class Account; def run; value; end; def value; 1; end; def self.run; value; end; def self.value; 2; end; def self.publish; run; end; end")
      index = described_class.new(root).call
      caller = index["methods"].find { |method| method["subject"] == "Account#run" }
      target = index["methods"].find { |method| method["subject"] == "Account#value" }
      expect(index["edges"]).to include(a_hash_including("from_id" => caller["id"], "to_id" => target["id"], "provenance" => "static_guess"))
      projection = Polyrun::Graph::Inspect.new(index).call(nil, ["--control-plane"])
      expect(projection.dig("control_plane", "lifecycle").map { |method| method["subject"] }).to include("Account#run", "Account.run")
      expect(described_class.new(root).call["reused"]).to be(true)
    end
  end

  it "plans repeated call replacements using byte locations and checks before apply" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/account.rb"), "# coding: UTF-8\nclass Account; LABEL = 'ää'; def self.value; helper + helper; end; def self.helper; 1; end; def self.replacement; 2; end; end")
      index = described_class.new(root).call
      operations = index["calls"].select { |node| node["name"] == "helper" }.map do |node|
        {"op" => "replace_call_name", "node" => node["id"], "expect" => node.slice("name", "fingerprint"), "replacement" => "replacement"}
      end
      File.write(File.join(root, "change.json"), JSON.generate("snapshot" => index["snapshot"], "operations" => operations))
      id = Polyrun::Graph::Planner.new(root).call("change.json").fetch("plan_id")
      plan = Polyrun::Graph::Plan.new(root, id)
      plan.check!
      plan.record_check!
      plan.apply!
      output, status = Open3.capture2e(Gem.ruby, "-Ilib", "-raccount", "-e", "puts Account.value", chdir: root)
      expect(status.exitstatus).to eq(0)
      expect(output.strip).to eq("4")
    end
  end
end
