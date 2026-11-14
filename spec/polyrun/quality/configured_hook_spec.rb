require "spec_helper"
require "fileutils"

RSpec.describe "configured quality hook activation" do
  it "loads the explicitly selected project settings without requiring an activation environment flag" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "polyrun.yml"), {"quality" => {"spec_quality" => {"enabled" => true}}}.to_yaml)
      probe = File.join(root, "probe_spec.rb")
      report = File.join(root, "quality.jsonl")
      File.write(probe, 'RSpec.describe("configured") { it("runs") { raise unless 2 + 2 == 4 } }')
      source = <<~RUBY
        require "polyrun/rspec_support"
        require "rspec/core"
        Polyrun::RSpecSupport.install_spec_quality!(root: ARGV[0], output_path: ARGV[1])
        exit RSpec::Core::Runner.run([ARGV[2]])
      RUBY
      env = {"POLYRUN_SPEC_QUALITY" => nil, "POLYRUN_SPEC_QUALITY_FRAGMENTS" => nil, "POLYRUN_CONFIG" => nil, "POLYRUN_COVERAGE_DISABLE" => "1"}
      output, status = Open3.capture2e(env, Gem.ruby, "-I", File.expand_path("../../../lib", __dir__), "-e", source, root, report, probe)
      expect(status.exitstatus).to eq(0), output
      expect(File).to exist(report)
      expect(JSON.parse(File.readlines(report).first)["example"]).to include("probe_spec.rb")
    end
  end
end
