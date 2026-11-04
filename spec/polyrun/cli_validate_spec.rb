require "spec_helper"
require "tmpdir"

RSpec.describe "polyrun validate", :aggregate_failures do
  it "rejects a config whose root is not a mapping" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", "- workers\n- 4\n")

        out, status = polyrun("validate")

        expect(status.success?).to be false
        expect(out).to include("config root must be a mapping")
      end
    end
  end

  it "exits 0 for a known-key config" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          version: 1
          partition:
            paths_build:
              all_glob: spec/**/*_spec.rb
          workers: 4
        YAML
        out, status = polyrun("validate")
        expect(status.success?).to be true
        expect(status.exitstatus).to eq(0)
        expect(out).to include("ok")
      end
    end
  end

  it "warns and exits 1 for unknown top-level keys" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          version: 1
          path_build:
            all_glob: spec/**/*_spec.rb
          partition:
            paths_build:
              all_glob: spec/**/*_spec.rb
        YAML
        out, status = polyrun("validate")
        expect(status.success?).to be false
        expect(status.exitstatus).to eq(1)
        expect(out).to match(/unknown top-level key.*path_build/)
      end
    end
  end
end
