require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Polyrun::Coverage::Formatter do
  describe ".multi" do
    it "runs all built-in formatters and returns paths" do
      Dir.mktmpdir do |dir|
        blob = {"/a.rb" => {"lines" => [nil, 1]}}
        result = Polyrun::Coverage::Result.new(blob, meta: {"title" => "T"}, groups: nil)
        fmt = described_class.multi(:json, :lcov, :cobertura, :console, :html, output_dir: dir, basename: "r")
        paths = fmt.format(result, output_dir: dir, basename: "r")
        expect(paths.keys.sort).to eq(%i[cobertura console html json lcov])
        expect(File.read(paths[:json])).to include("coverage")
        expect(File.read(paths[:html])).to include("T", "/a.rb")
        expect(File.read(paths[:lcov])).to include("SF:/a.rb")
        expect(File.read(paths[:cobertura])).to include("<coverage")
        expect(File.read(paths[:console])).to include("Polyrun coverage summary")
      end
    end
  end

  describe Polyrun::Coverage::Formatter::MultiFormatter do
    it "composes custom formatters" do
      Dir.mktmpdir do |dir|
        custom = Class.new(Polyrun::Coverage::Formatter::Base) do
          define_method(:write_files) do |result, output_dir, basename|
            path = File.join(output_dir, "#{basename}-custom.txt")
            File.write(path, result.files.size.to_s)
            {custom: path}
          end
        end
        blob = {"/x.rb" => {"lines" => [1]}}
        result = Polyrun::Coverage::Result.new(blob)
        multi = described_class.new([
          Polyrun::Coverage::Formatter::JsonFormatter.new(output_dir: dir, basename: "m"),
          custom.new(output_dir: dir, basename: "m")
        ])
        paths = multi.format(result, output_dir: dir, basename: "m")
        expect(paths[:json]).to end_with("m.json")
        expect(paths[:custom]).to end_with("m-custom.txt")
        expect(File.read(paths[:custom])).to eq("1")
      end
    end
  end
end
