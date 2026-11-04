require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "start skip env aliases", :aggregate_failures do
  it "treats POLYRUN_SKIP_PREPARE like POLYRUN_START_SKIP_PREPARE" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: ruby -e 'raise "should_skip"'
          start:
            prepare: true
          partition:
            paths_file: spec/list.txt
            paths_build:
              all_glob: spec/**/*_spec.rb
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/list.txt", "spec/a_spec.rb\n")
        File.write("spec/a_spec.rb", "RSpec.describe('a') { it('x') { expect(1).to eq(1) } }\n")

        # start would run prepare then parallel; skip prepare via canonical env
        # Use dry path: only bootstrap check via doctor-equivalent is hard; call start with skip
        # and ensure prepare command is not executed (no raise). Stub by using prepare that
        # writes a marker; skip should leave marker absent.
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: ruby -e 'File.write("prepared.marker", "1")'
          start:
            prepare: true
            databases: false
          partition:
            paths_file: spec/list.txt
            paths_build:
              all_glob: spec/**/*_spec.rb
        YAML

        _out, status = polyrun(
          "start", "--workers", "1", "--", "ruby", "-e", "exit 0",
          env: {"POLYRUN_SKIP_PREPARE" => "1", "POLYRUN_SKIP_PATHS_BUILD" => "1"}
        )
        expect(File.file?("prepared.marker")).to be false
        # start may still fail on empty/missing rspec; marker absence is the contract
        expect(status.exitstatus).not_to eq(nil)
      end
    end
  end

  it "still honors legacy POLYRUN_START_SKIP_PREPARE" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("polyrun.yml", <<~YAML)
          prepare:
            recipe: shell
            command: ruby -e 'File.write("prepared.marker", "1")'
          start:
            prepare: true
            databases: false
          partition:
            paths_file: spec/list.txt
            paths_build:
              all_glob: spec/**/*_spec.rb
        YAML
        FileUtils.mkdir_p("spec")
        File.write("spec/list.txt", "spec/a_spec.rb\n")

        polyrun(
          "start", "--workers", "1", "--", "ruby", "-e", "exit 0",
          env: {"POLYRUN_START_SKIP_PREPARE" => "1", "POLYRUN_SKIP_PATHS_BUILD" => "1"}
        )
        expect(File.file?("prepared.marker")).to be false
      end
    end
  end
end
