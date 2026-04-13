require "spec_helper"

RSpec.describe "polyrun.gemspec" do
  it "declares no runtime dependencies" do
    root = File.expand_path("../..", __dir__)
    spec = Gem::Specification.load(File.join(root, "polyrun.gemspec"))
    runtime = spec.dependencies.select { |d| d.type == :runtime }
    expect(runtime).to be_empty, "expected zero runtime deps; got: #{runtime.map(&:name)}"
  end
end
