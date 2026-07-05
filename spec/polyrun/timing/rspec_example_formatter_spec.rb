require "spec_helper"
require "polyrun/timing/rspec_example_formatter"
require "json"
require "open3"
require "stringio"
require "tmpdir"

RSpec.describe "Polyrun example timing" do
  describe Polyrun::Timing::RSpecExampleFormatter do
    def example_notification(path:, line:, run_time:, pending: false)
      metadata = {absolute_file_path: path, line_number: line}
      result = double("execution_result", run_time: run_time)
      example = double(
        "example",
        metadata: metadata,
        execution_result: result,
        pending?: pending
      )
      double("notification", example: example)
    end

    it "writes path:line seconds to JSON on close" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "timing.json")
        formatter = described_class.new(StringIO.new)
        allow(formatter).to receive(:timing_output_path).and_return(out)

        formatter.example_finished(example_notification(path: __FILE__, line: 42, run_time: 0.25))
        formatter.close(nil)

        data = JSON.parse(File.read(out))
        key = "#{File.expand_path(__FILE__)}:42"
        expect(data[key]).to eq(0.25)
      end
    end

    it "skips pending examples" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "timing.json")
        formatter = described_class.new(StringIO.new)
        allow(formatter).to receive(:timing_output_path).and_return(out)

        formatter.example_finished(example_notification(path: __FILE__, line: 1, run_time: 1.0, pending: true))
        formatter.close(nil)

        expect(JSON.parse(File.read(out))).to eq({})
      end
    end

    it "keeps the maximum run time per path:line key" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "timing.json")
        formatter = described_class.new(StringIO.new)
        allow(formatter).to receive(:timing_output_path).and_return(out)

        formatter.example_finished(example_notification(path: __FILE__, line: 7, run_time: 0.2))
        formatter.example_finished(example_notification(path: __FILE__, line: 7, run_time: 0.9))
        formatter.close(nil)

        key = "#{File.expand_path(__FILE__)}:7"
        expect(JSON.parse(File.read(out))[key]).to eq(0.9)
      end
    end

    it "uses POLYRUN_EXAMPLE_TIMING_OUT when set" do
      old = ENV["POLYRUN_EXAMPLE_TIMING_OUT"]
      ENV["POLYRUN_EXAMPLE_TIMING_OUT"] = "custom_timing.json"
      begin
        formatter = described_class.new(StringIO.new)
        expect(formatter.timing_output_path).to eq("custom_timing.json")
      ensure
        old ? ENV.store("POLYRUN_EXAMPLE_TIMING_OUT", old) : ENV.delete("POLYRUN_EXAMPLE_TIMING_OUT")
      end
    end
  end

  describe "Polyrun::RSpec.install_example_timing!" do
    it "writes per-example timing JSON in a subprocess" do
      root = File.expand_path("../..", __dir__)
      lib = File.join(root, "lib")
      Dir.mktmpdir do |dir|
        timing_out = File.join(dir, "timing.json")
        spec = File.join(dir, "one_spec.rb")
        File.write(spec, <<~RUBY)
          require "polyrun/rspec"
          Polyrun::RSpec.install_example_timing!(output_path: #{timing_out.inspect})
          RSpec.describe "timing" do
            it "runs" do
              expect(1).to eq(1)
            end
          end
        RUBY
        out, status = Open3.capture2e(
          {"RUBYOPT" => "-I#{lib}"},
          Gem.ruby, "-S", "rspec", spec, "--format", "progress",
          chdir: dir
        )
        expect(status.exitstatus).to eq(0), out
        data = JSON.parse(File.read(timing_out))
        expect(data.values.first).to be_a(Float)
        expect(data.keys.first).to match(/:\d+\z/)
      end
    end
  end
end
