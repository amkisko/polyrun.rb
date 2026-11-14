require "spec_helper"
require "polyrun/mutation/runner"
require "fileutils"

RSpec.describe "Polyrun mutation operators" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      example.run
    end
  end

  def run_mutations(source, assertion, operators)
    File.write(File.join(@root, "lib/account.rb"), source)
    command = [Gem.ruby, "-Ilib", "-raccount", "-e", assertion]
    Polyrun::Mutation::Runner.new(root: @root, arguments: command, operators: operators).call(["Account.*"])
  end

  it "changes comparison and arithmetic behavior through the operator family" do
    source = "class Account; def self.valid?(amount); amount >= 2; end; def self.total(amount); amount + 2; end; end"
    assertion = "abort unless Account.valid?(2) && !Account.valid?(1) && Account.total(3) == 5"
    report = run_mutations(source, assertion, [Polyrun::Mutation::Operators::Operator.new])
    expect(report).to include("ok" => true, "mutations" => 2, "killed" => 2, "survived" => 0)
  end

  it "changes string, collection, boolean, and nil return contracts" do
    source = "class Account; def self.values; ['ready', {a: true}, false, nil]; end; end"
    assertion = "abort unless Account.values == ['ready', {a: true}, false, nil]"
    report = run_mutations(source, assertion, [Polyrun::Mutation::Operators::Literal.new])
    expect(report).to include("ok" => true, "survived" => 0)
    expect(report["killed"]).to eq(6)
  end

  it "runs a consumer-supplied operator through the same baseline and isolation contract" do
    operator = lambda do |node|
      node.is_a?(Prism::IntegerNode) ? [[node.location, "42", "answer"]] : []
    end
    report = run_mutations("class Account; def self.value; 2; end; end", "abort unless Account.value == 2", [operator])
    expect(report).to include("ok" => true, "mutations" => 1, "killed" => 1)
    expect(report["results"].first).to include("operator" => "answer", "code" => "KILLED")
  end
end
