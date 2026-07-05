require "spec_helper"
require "polyrun/quick/matchers"
require "polyrun/quick/errors"

RSpec.describe Polyrun::Quick::Matchers do
  let(:assertions) { Class.new { include Polyrun::Quick::Matchers }.new }

  it "eq matcher passes and fails with messages" do
    assertions.expect(1).to assertions.eq(1)
    expect { assertions.expect(2).to assertions.eq(1) }
      .to raise_error(Polyrun::Quick::AssertionFailed, /expected 1/)
    expect { assertions.expect(1).not_to assertions.eq(1) }
      .to raise_error(Polyrun::Quick::AssertionFailed, /not to eq/)
  end

  it "truthy and falsey matchers" do
    assertions.expect(true).to assertions.be_truthy
    assertions.expect(nil).to assertions.be_falsey
    expect { assertions.expect(false).to assertions.be_truthy }
      .to raise_error(Polyrun::Quick::AssertionFailed, /truthy/)
    expect { assertions.expect(false).not_to assertions.be_falsey }
      .to raise_error(Polyrun::Quick::AssertionFailed, /expected truthy/)
  end

  it "include matcher requires enumerable-like values" do
    assertions.expect("hello").to assertions.include("ell")
    expect { assertions.expect("a").to assertions.include("b") }
      .to raise_error(Polyrun::Quick::AssertionFailed, /include/)
    expect { assertions.expect(1).to assertions.include(1) }
      .to raise_error(Polyrun::Quick::AssertionFailed)
  end

  it "match matcher uses regex on strings" do
    assertions.expect("abc").to assertions.match(/a/)
    expect { assertions.expect("x").to assertions.match(/a/) }
      .to raise_error(Polyrun::Quick::AssertionFailed, /match/)
    expect { assertions.expect("abc").not_to assertions.match(/a/) }
      .to raise_error(Polyrun::Quick::AssertionFailed)
  end
end
