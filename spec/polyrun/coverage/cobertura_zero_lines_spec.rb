require "spec_helper"

RSpec.describe Polyrun::Coverage::CoberturaZeroLines do
  describe ".extract" do
    it "finds zero-hit lines under prefix" do
      xml = <<~XML
        <coverage>
          <package>
            <classes>
              <class filename="lib/foo.rb">
                <lines>
                  <line number="1" hits="1"/>
                  <line number="2" hits="0"/>
                </lines>
              </class>
            </classes>
          </package>
        </coverage>
      XML
      u = described_class.extract(xml, filename_prefix: "lib/")
      expect(u.map { |e| [e[:file], e[:line]] }).to eq([["lib/foo.rb", 2]])
    end

    it "ignores classes outside prefix" do
      xml = <<~XML
        <class filename="vendor/x.rb">
          <line number="1" hits="0"/>
        </class>
      XML
      expect(described_class.extract(xml, filename_prefix: "lib/")).to be_empty
    end
  end

  describe ".run" do
    it "prints uncovered lines when SHOW_ZERO_COVERAGE=1 and file exists" do
      Dir.mktmpdir do |dir|
        xml = File.join(dir, "c.xml")
        File.write(xml, <<~XML)
          <class filename="lib/a.rb">
            <line number="5" hits="0"/>
          </class>
        XML
        out = StringIO.new
        begin
          Polyrun::Log.stdout = out
          ENV["SHOW_ZERO_COVERAGE"] = "1"
          described_class.run(xml_path: xml, filename_prefix: "lib/")
        ensure
          Polyrun::Log.reset_io!
          ENV.delete("SHOW_ZERO_COVERAGE")
        end
        expect(out.string).to include("lib/a.rb:5")
      end
    end

    it "no-ops when env unset" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "c.xml")
        File.write(path, "<class/>")
        ENV.delete("SHOW_ZERO_COVERAGE")
        expect { described_class.run(xml_path: path) }.not_to raise_error
      end
    end
  end
end
