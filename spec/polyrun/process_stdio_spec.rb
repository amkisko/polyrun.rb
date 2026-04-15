require "spec_helper"

RSpec.describe Polyrun::ProcessStdio do
  describe ".inherit_stdio_spawn_wait" do
    it "runs a trivial command" do
      st = described_class.inherit_stdio_spawn_wait(nil, RbConfig.ruby, "-e", "exit 0")
      expect(st.success?).to be true
    end

    it "suppresses child stdio when silent: true" do
      st = described_class.inherit_stdio_spawn_wait(
        nil,
        RbConfig.ruby,
        "-e",
        "STDOUT.puts 'x'; STDERR.puts 'y'",
        silent: true
      )
      expect(st.success?).to be true
    end
  end

  describe ".spawn_wait" do
    it "returns empty captures on inherited stdio" do
      st, out, err = described_class.spawn_wait(nil, RbConfig.ruby, "-e", "exit 0", silent: false)
      expect(st.success?).to be true
      expect(out).to eq("")
      expect(err).to eq("")
    end

    it "returns stderr and stdout when silent and the child fails" do
      st, out, err = described_class.spawn_wait(
        nil,
        RbConfig.ruby,
        "-e",
        "STDOUT.puts 'o'; STDERR.puts 'e'; exit 1",
        silent: true
      )
      expect(st.success?).to be false
      expect(out).to include("o")
      expect(err).to include("e")
    end
  end
end
