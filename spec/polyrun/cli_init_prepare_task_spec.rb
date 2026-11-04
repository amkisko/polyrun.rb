require "spec_helper"
require "tmpdir"

RSpec.describe "polyrun init rails-prepare-task", :aggregate_failures do
  it "writes a rake task that invokes polyrun prepare and documents skip env" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        out, status = polyrun("init", "--profile", "rails-prepare-task")
        expect(status.success?).to be true
        expect(out).to include("wrote")
        path = "lib/tasks/polyrun_prepare.rake"
        expect(File.file?(path)).to be true
        body = File.read(path)
        expect(body).to include("namespace :polyrun")
        expect(body).to include("task prepare")
        expect(body).to include("POLYRUN_SKIP_PREPARE")
        expect(body).to match(/polyrun prepare|Prepare::/)
      end
    end
  end

  it "lists rails-prepare-task in init --list" do
    out, status = polyrun("init", "--list")
    expect(status.success?).to be true
    expect(out).to include("rails-prepare-task")
  end
end
