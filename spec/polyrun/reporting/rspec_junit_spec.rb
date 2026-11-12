require "spec_helper"
require "polyrun/rspec_support"
require "polyrun/reporting/rspec_junit"

RSpec.describe Polyrun::Reporting::RspecJunit do
  describe ".install!" do
    it "no-ops when only_if is false (does not load RSpec formatters)" do
      expect do
        described_class.install!(only_if: -> { false })
      end.not_to raise_error
    end

    it "configures ::RSpec when Polyrun::RSpecSupport is already defined" do
      expect(Polyrun.const_defined?(:RSpecSupport, false)).to be true

      Dir.mktmpdir do |dir|
        expect do
          described_class.install!(
            json_path: File.join(dir, "rspec.json"),
            junit_path: File.join(dir, "junit.xml"),
            only_if: -> { true }
          )
        end.not_to raise_error
      end
    end
  end
end
