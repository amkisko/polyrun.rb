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

    it "truncates very large failure captures" do
      big = "x" * 40_000
      st, out, _err = described_class.spawn_wait(
        nil,
        RbConfig.ruby,
        "-e",
        "STDOUT.print #{big.inspect}; exit 1",
        silent: true
      )
      expect(st.success?).to be false
      expect(out).to include("bytes total")
    end

    it "supports chdir when spawning" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "marker"), "1")
        st, = described_class.spawn_wait(nil, RbConfig.ruby, "-e", "exit(File.file?('marker') ? 0 : 1)", chdir: dir, silent: true)
        expect(st.success?).to be true
      end
    end
  end

  describe ".format_failure_message" do
    it "includes stdout and stderr sections" do
      status = instance_double(Process::Status, exitstatus: 3)
      msg = described_class.format_failure_message("rspec", status, "out", "err")
      expect(msg).to include("exit 3")
      expect(msg).to include("stdout")
      expect(msg).to include("stderr")
    end
  end
end
