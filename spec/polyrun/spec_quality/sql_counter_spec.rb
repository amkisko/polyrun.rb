require "spec_helper"
require "polyrun/spec_quality/sql_counter"

RSpec.describe Polyrun::SpecQuality::SqlCounter do
  around do |ex|
    described_class.uninstall!
    ex.run
  ensure
    described_class.uninstall!
  end

  it "install! subscribes when ActiveSupport::Notifications is available" do
    skip "ActiveSupport not loaded" unless described_class.notifications_available?

    expect(described_class.install!).to be true
    expect(described_class.install!).to be true
  end

  it "uninstall! clears the subscriber" do
    skip "ActiveSupport not loaded" unless described_class.notifications_available?

    described_class.install!
    described_class.uninstall!
    expect(described_class.install!).to be true
  end
end
