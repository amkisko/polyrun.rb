require "spec_helper"
require "polyrun/mutation/subjects"
require "fileutils"
require "json"
require "digest"

RSpec.describe Polyrun::Mutation::Subjects do
  it "selects observed subjects and rejects incomplete observations" do
    Dir.mktmpdir do |root|
      path = File.join(root, "observed.json")
      trace = {"provenance" => "observed", "truncated" => false, "calls" => [{"subject" => "Account#save"}]}
      File.write(path, JSON.generate(trace))
      expect(described_class.from_observation(path)).to eq(["Account#save"])
      File.write(path, JSON.generate(trace.merge("truncated" => true)))
      expect { described_class.from_observation(path) }.to raise_error(ArgumentError, /truncated/)
      File.write(path, JSON.generate(trace.merge("calls" => [nil])))
      expect { described_class.from_observation(path) }.to raise_error(ArgumentError, /subject/)
    end
  end

  it "selects changed instance and singleton methods from staged source without loading it" do
    Dir.mktmpdir do |root|
      tree = File.join(root, ".polyrun/graph/plans/p123/tree")
      FileUtils.mkdir_p(File.join(tree, "lib"))
      FileUtils.mkdir_p(File.join(root, "lib"))
      original = "module Shop; class Account; def save; old; end; def self.find; old; end; def same; 1; end; end; end"
      File.write(File.join(root, "lib/account.rb"), original)
      File.write(File.join(tree, "lib/account.rb"), original.gsub("old", "new"))
      File.write(File.join(root, ".polyrun/graph/plans/p123/meta.json"), JSON.generate("pre_hashes" => {"lib/account.rb" => Digest::SHA256.hexdigest(original)}))
      expect(described_class.from_plan(root, "p123")).to eq(["Shop::Account#save", "Shop::Account.find"])
    end
  end

  it "requires explicit subjects when constant owners need runtime resolution" do
    Dir.mktmpdir do |root|
      tree = File.join(root, ".polyrun/graph/plans/p123/tree")
      FileUtils.mkdir_p(File.join(tree, "lib"))
      FileUtils.mkdir_p(File.join(root, "lib"))
      original = "module Shop; class Shop::Account; def save; old; end; end; end"
      File.write(File.join(root, "lib/account.rb"), original)
      File.write(File.join(tree, "lib/account.rb"), original.sub("old", "new"))
      File.write(File.join(root, ".polyrun/graph/plans/p123/meta.json"), JSON.generate("pre_hashes" => {"lib/account.rb" => Digest::SHA256.hexdigest(original)}))
      expect { described_class.from_plan(root, "p123") }.to raise_error(ArgumentError, /explicit/)
      original = "class factory::Account; def save; old; end; end"
      File.write(File.join(root, "lib/account.rb"), original)
      File.write(File.join(tree, "lib/account.rb"), original.sub("old", "new"))
      File.write(File.join(root, ".polyrun/graph/plans/p123/meta.json"), JSON.generate("pre_hashes" => {"lib/account.rb" => Digest::SHA256.hexdigest(original)}))
      expect { described_class.from_plan(root, "p123") }.to raise_error(ArgumentError, /explicit/)
    end
  end
end
