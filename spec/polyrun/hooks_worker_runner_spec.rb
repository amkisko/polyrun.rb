require "spec_helper"

RSpec.describe Polyrun::Hooks::WorkerRunner do
  around do |example|
    Polyrun::Hooks::Dsl.clear_cache!
    example.run
    Polyrun::Hooks::Dsl.clear_cache!
  end

  it "returns 0 when POLYRUN_HOOKS_RUBY_FILE is unset" do
    ENV.delete("POLYRUN_HOOKS_RUBY_FILE")
    expect(described_class.run!(:before_worker)).to eq(0)
  end

  it "runs the DSL phase and returns 0" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("w.rb", <<~RUBY)
          before(:each) { File.write("ran.txt", "1") }
        RUBY
        ENV["POLYRUN_HOOKS_RUBY_FILE"] = File.expand_path("w.rb", dir)
        expect(described_class.run!(:before_worker)).to eq(0)
        expect(File.read(File.join(dir, "ran.txt"))).to eq("1")
      end
    end
  end

  it "returns 1 when the block raises" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write("w.rb", "before(:each) { raise \"nope\" }")
        ENV["POLYRUN_HOOKS_RUBY_FILE"] = File.expand_path("w.rb", dir)
        expect(described_class.run!(:before_worker)).to eq(1)
      end
    end
  end
end
