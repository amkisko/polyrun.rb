require "spec_helper"
require "polyrun/spec_quality/config"

RSpec.describe "shared spec quality settings" do
  it "enables collection and configures thresholds through the main settings file" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "polyrun.yml"), {"quality" => {"spec_quality" => {"enabled" => true, "min_line_churn" => 7, "sample" => 0.25}}}.to_yaml)
      with_chdir(root) do
        expect(Polyrun::SpecQuality::Config.enabled?({})).to be(true)
        settings = Polyrun::SpecQuality::Config.load(root: root, env: {})
        expect(settings).to include("min_line_churn" => 7, "sample" => 0.25)
        expect(Polyrun::SpecQuality::Config.enabled?({"POLYRUN_SPEC_QUALITY_DISABLE" => "1"})).to be(false)
      end
    end
  end
end
