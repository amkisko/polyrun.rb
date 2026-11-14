require "spec_helper"
require "fileutils"

RSpec.describe "root worker timeouts" do
  it "applies the shared timeout to ordinary parallel test workers" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "spec"))
      File.write(File.join(root, "spec/a_spec.rb"), "")
      File.write(File.join(root, "polyrun.yml"), {"workers" => 1, "timeout" => 0.1}.to_yaml)
      with_chdir(root) do
        output, status = polyrun("run-shards", "--", Gem.ruby, "-e", "sleep 1")
        expect(status.exitstatus).to eq(1), output
        expect(output).to include("WORKER TIMEOUT", "exit 124")
      end
    end
  end
end
