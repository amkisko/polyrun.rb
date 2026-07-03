require "spec_helper"
require "polyrun/spec_quality/config"

RSpec.describe Polyrun::SpecQuality::Config do
  it "is enabled when POLYRUN_SPEC_QUALITY=1" do
    expect(described_class.enabled?({"POLYRUN_SPEC_QUALITY" => "1"})).to be true
  end

  it "loads yaml thresholds" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "polyrun_spec_quality.yml"), <<~YAML)
        min_line_churn: 99
        sample: 0.25
      YAML
      cfg = described_class.load(root: dir)
      expect(cfg["min_line_churn"]).to eq(99)
      expect(cfg["sample"]).to eq(0.25)
    end
  end

  it "matches ignore_examples patterns" do
    expect(described_class.ignored_example?("spec/foo_spec.rb:10", ["foo_spec"])).to be true
    expect(described_class.ignored_example?("spec/bar_spec.rb:1", ["foo_spec"])).to be false
  end
end
