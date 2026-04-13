require "spec_helper"

RSpec.describe Polyrun::Timing::Summary do
  describe ".format_slow_files" do
    it "sorts by duration descending" do
      merged = {"/slow.rb" => 9.0, "/fast.rb" => 1.0, "/mid.rb" => 3.0}
      text = described_class.format_slow_files(merged, top: 2)
      expect(text).to include("/slow.rb")
      expect(text).to include("/mid.rb")
      expect(text).not_to include("/fast.rb")
    end

    it "handles empty hash" do
      expect(described_class.format_slow_files({})).to include("(no data)")
    end
  end
end
