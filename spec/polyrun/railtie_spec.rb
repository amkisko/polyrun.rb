require "spec_helper"
require "open3"

RSpec.describe "Polyrun::Railtie" do
  it "is not loaded when Rails is absent" do
    expect(Polyrun.const_defined?(:Railtie, false)).to be false
  end

  it "registers the polyrun railtie name when Rails::Railtie is defined" do
    lib = File.expand_path("../../lib", __dir__)
    script = <<~'RUBY'
      $LOAD_PATH.unshift(ARGV[0])
      unless defined?(Rails::Railtie)
        module Rails
          class Railtie
            class << self
              def inherited(subclass)
                subclass.extend(ClassMethods)
              end
            end
            module ClassMethods
              def railtie_name(name = nil)
                if name
                  @polyrun_railtie_name = name
                else
                  @polyrun_railtie_name
                end
              end
            end
          end
        end
      end
      require "polyrun/railtie"
      exit(Polyrun::Railtie.railtie_name == :polyrun ? 0 : 1)
    RUBY
    _err, status = Open3.capture2e(Gem.ruby, "-e", script, lib)
    expect(status.exitstatus).to eq(0), -> { _err }
  end
end
