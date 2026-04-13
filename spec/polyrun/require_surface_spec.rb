require "spec_helper"
require "open3"

RSpec.describe 'require "polyrun"' do
  it "does not load Reporting::RspecJunit (opt-in require only)" do
    lib = File.expand_path("../../lib", __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift(#{lib.inspect})
      require "polyrun"
      exit(Polyrun::Reporting.const_defined?(:RspecJunit, false) ? 1 : 0)
    RUBY
    _err, status = Open3.capture2e(Gem.ruby, "-e", script)
    expect(status.exitstatus).to eq(0)
  end
end
