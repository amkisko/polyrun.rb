require "spec_helper"

RSpec.describe Polyrun::Reporting::RspecJunit do
  describe ".install!" do
    it "no-ops when only_if is false (does not load RSpec formatters)" do
      expect do
        described_class.install!(only_if: -> { false })
      end.not_to raise_error
    end
  end
end
