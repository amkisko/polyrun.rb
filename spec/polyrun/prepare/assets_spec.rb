require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Polyrun::Prepare::Assets do
  it "digest_sources is stable for file content" do
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.txt")
      File.write(a, "hello")
      d1 = described_class.digest_sources(a)
      d2 = described_class.digest_sources(a)
      expect(d1).to eq(d2)
      expect(d1.length).to eq(32) # md5 hex
    end
  end

  it "detects stale marker" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "x.txt")
      File.write(f, "x")
      m = File.join(dir, "marker")
      described_class.write_marker!(m, f)
      expect(described_class.stale?(m, f)).to be false
      File.write(f, "y")
      expect(described_class.stale?(m, f)).to be true
    end
  end

  it "precompile! forwards silent to ProcessStdio.spawn_wait" do
    Dir.mktmpdir do |dir|
      exe = File.join(dir, "bin", "rails")
      FileUtils.mkdir_p(File.dirname(exe))
      File.write(exe, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, exe)
      ok = instance_double(Process::Status, success?: true)
      allow(Polyrun::ProcessStdio).to receive(:spawn_wait).and_return([ok, "", ""])
      expect(described_class.precompile!(rails_root: dir, silent: false)).to be true
      expect(Polyrun::ProcessStdio).to have_received(:spawn_wait).with(
        nil, exe, "assets:precompile", chdir: dir, silent: false
      )
    end
  end
end
