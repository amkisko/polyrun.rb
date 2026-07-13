require "spec_helper"
require "polyrun/coverage/example_diff"

RSpec.describe Polyrun::Coverage::ExampleDiff do
  describe ".diff" do
    it "computes positive line deltas only" do
      before = {"/app/a.rb" => {"lines" => [1, 0, nil, 2]}}
      after = {"/app/a.rb" => {"lines" => [3, 1, nil, 2]}}
      d = described_class.diff(before, after)
      expect(d[:unique_lines]).to eq(2)
      expect(d[:line_churn]).to eq(3)
      expect(d[:max_line_churn]).to eq(2)
      expect(d[:lines]).to contain_exactly(["/app/a.rb", 1, 2], ["/app/a.rb", 2, 1])
    end

    it "matches blob diff when after is a raw Coverage.peek_result-shaped hash" do
      before = {"/app/a.rb" => {"lines" => [1, 0, nil, 2]}}
      after_blob = {"/app/a.rb" => {"lines" => [3, 1, nil, 2]}}
      after_peek = {"/app/a.rb" => {lines: [3, 1, nil, 2]}}
      expect(described_class.diff(before, after_peek)).to eq(described_class.diff(before, after_blob))
    end

    it "handles newly loaded files in after blob" do
      before = {}
      after = {"/lib/x.rb" => {"lines" => [nil, 1]}}
      d = described_class.diff(before, after)
      expect(d[:unique_lines]).to eq(1)
      expect(d[:lines]).to eq([["/lib/x.rb", 2, 1]])
    end
  end

  describe ".snapshot_peek" do
    it "dupes line arrays so later stdlib mutations do not change the snapshot" do
      raw = {"/app/a.rb" => {lines: [1, 2]}}
      snapshot = described_class.snapshot_peek(raw)
      raw["/app/a.rb"][:lines][0] = 99
      expect(snapshot["/app/a.rb"]["lines"]).to eq([1, 2])
    end
  end

  describe ".apply_track_under" do
    it "keeps only paths under track_under" do
      root = Dir.mktmpdir
      lib = File.join(root, "lib", "a.rb")
      spec = File.join(root, "spec", "b.rb")
      FileUtils.mkdir_p(File.dirname(lib))
      FileUtils.mkdir_p(File.dirname(spec))

      delta = {
        lines: [[lib, 1, 1], [spec, 5, 2]],
        unique_lines: 2,
        line_churn: 3,
        max_line_churn: 2
      }
      out = described_class.apply_track_under(delta, root: root, track_under: %w[lib])
      expect(out[:lines]).to eq([[lib, 1, 1]])
      expect(out[:unique_lines]).to eq(1)
      expect(out[:line_churn]).to eq(1)
    end
  end
end
