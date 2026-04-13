require "spec_helper"
require "json"
require "open3"
require "polyrun/quick"
require "tmpdir"

RSpec.describe Polyrun::Quick do
  describe Polyrun::Quick::Runner do
    it "runs passing examples and returns 0" do
      Dir.mktmpdir do |dir|
        f = File.join(dir, "ok.rb")
        File.write(f, <<~RUBY)
          describe "g" do
            it "a" do
              assert_equal 1, 1
            end
          end
        RUBY

        out = StringIO.new
        err = StringIO.new
        code = described_class.run(paths: [f], out: out, err: err)
        expect(code).to eq(0)
        expect(out.string).to include("1 passed")
      end
    end

    it "counts failures and returns 1" do
      Dir.mktmpdir do |dir|
        f = File.join(dir, "bad.rb")
        File.write(f, <<~RUBY)
          describe "g" do
            it "a" do
              assert_equal 1, 2
            end
          end
        RUBY

        out = StringIO.new
        err = StringIO.new
        code = described_class.run(paths: [f], out: out, err: err)
        expect(code).to eq(1)
        expect(err.string).to include("FAIL")
        expect(out.string).to include("0 passed")
      end
    end

    it "returns 2 when no files match" do
      code = described_class.run(paths: [File.join(Dir.tmpdir, "polyrun_quick_empty_xyz")])
      expect(code).to eq(2)
    end

    it "writes a coverage fragment when POLYRUN_COVERAGE=1 (subprocess)" do
      Dir.mktmpdir do |dir|
        f = File.join(dir, "cov.rb")
        File.write(f, <<~RUBY)
          describe "g" do
            it "a" do
              assert_equal 1, 1
            end
          end
        RUBY
        lib = File.expand_path("../../lib", __dir__)
        env = ENV.to_h.merge("POLYRUN_COVERAGE" => "1")
        env.delete("POLYRUN_COVERAGE_DISABLE")
        _out, _err, st = Open3.capture3(
          env,
          RbConfig.ruby,
          "-I#{lib}",
          "-rpolyrun",
          "-e",
          "exit(Polyrun::CLI.run([\"quick\", #{f.inspect}]))",
          chdir: dir
        )
        expect(st.exitstatus).to eq(0)
        frag = File.join(dir, "coverage", "polyrun-fragment-0.json")
        expect(File.file?(frag)).to be true
        meta = JSON.parse(File.read(frag))["meta"]
        expect(meta["command_name"]).to eq("polyrun quick")
      end
    end
  end
end
