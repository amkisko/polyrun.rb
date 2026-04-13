require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Reporting::Junit do
  describe ".write_from_json_file / .parse_input / RSpec JSON" do
    it "converts RSpec JSON to JUnit with testcase counts" do
      Dir.mktmpdir do |dir|
        inp = File.join(dir, "rspec.json")
        File.write(inp, JSON.dump({
          "examples" => [
            {
              "full_description" => "Foo does x",
              "file_path" => "./spec/foo_spec.rb",
              "line_number" => 1,
              "run_time" => 0.01,
              "status" => "passed"
            },
            {
              "description" => "fails",
              "full_description" => "Foo fails",
              "file_path" => "./spec/foo_spec.rb",
              "line_number" => 2,
              "run_time" => 0.02,
              "status" => "failed",
              "exception" => {
                "message" => "expected: 1",
                "backtrace" => ["spec/foo_spec.rb:2:in `block'"]
              }
            },
            {
              "full_description" => "Foo pending",
              "file_path" => "./spec/foo_spec.rb",
              "status" => "pending",
              "run_time" => 0.001
            }
          ]
        }))
        out = File.join(dir, "junit.xml")
        described_class.write_from_json_file(inp, output_path: out)
        xml = File.read(out)
        expect(xml).to match(/tests="3"/)
        expect(xml).to match(/failures="1"/)
        expect(xml).to match(/skipped="1"/)
        expect(xml).to include("<failure message=")
        expect(xml).to include("<skipped/>")
      end
    end
  end

  describe ".emit_xml from Polyrun canonical testcase JSON" do
    it "emits testsuite with passed and error" do
      doc = {
        "name" => "MySuite",
        "hostname" => "ci",
        "testcases" => [
          {"classname" => "a.rb", "name" => "ok", "time" => 0.1, "status" => "passed"},
          {
            "classname" => "b.rb",
            "name" => "boom",
            "time" => 0.2,
            "status" => "error",
            "failure" => {"message" => "err", "body" => "stack"}
          }
        ]
      }
      xml = described_class.emit_xml(doc)
      expect(xml).to include('tests="2"')
      expect(xml).to include('failures="0"')
      expect(xml).to include('errors="1"')
      expect(xml).to include("<error message=")
    end
  end

  describe ".parse_input" do
    it "raises on unsupported JSON" do
      expect do
        described_class.parse_input({"foo" => 1})
      end.to raise_error(Polyrun::Error, /examples.*testcases/)
    end
  end
end
