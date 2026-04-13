require "spec_helper"

RSpec.describe Polyrun::Coverage::Filter do
  describe ".reject_matching_paths" do
    it "drops paths matching any substring" do
      blob = {
        "/app/lib/a.rb" => {"lines" => [1]},
        "/app/lib/tasks/x.rb" => {"lines" => [1]},
        "/app/lib/generators/y.rb" => {"lines" => [1]}
      }
      out = described_class.reject_matching_paths(blob, ["/lib/tasks/", "/lib/generators/"])
      expect(out.keys).to eq(["/app/lib/a.rb"])
    end

    it "returns blob unchanged when patterns empty" do
      blob = {"/a.rb" => {"lines" => [1]}}
      expect(described_class.reject_matching_paths(blob, [])).to eq(blob)
    end
  end
end
