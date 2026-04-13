require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Prepare::Artifacts do
  describe ".write!" do
    it "writes polyrun-artifacts.json with version and artifact entries" do
      Dir.mktmpdir do |root|
        file = File.join(root, "marker.txt")
        File.write(file, "x")
        path = described_class.write!(
          root: root,
          recipe: "test",
          entries: [{"path" => file, "kind" => "file"}],
          dry_run: false
        )
        expect(path).to eq(File.join(root, "polyrun-artifacts.json"))
        doc = JSON.parse(File.read(path))
        expect(doc["version"]).to eq(1)
        expect(doc["recipe"]).to eq("test")
        expect(doc["dry_run"]).to be false
        expect(doc["artifacts"].first["path"]).to eq(file)
        expect(doc["artifacts"].first["digest"]).to start_with("sha256:")
      end
    end
  end

  describe ".normalize_entry" do
    it "preserves explicit digest when path exists" do
      Dir.mktmpdir do |root|
        f = File.join(root, "f.txt")
        File.write(f, "body")
        e = described_class.normalize_entry({"path" => f, "kind" => "file", "digest" => "sha256:explicit"})
        expect(e["digest"]).to eq("sha256:explicit")
      end
    end
  end
end
