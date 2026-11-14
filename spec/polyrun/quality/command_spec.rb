require "spec_helper"
require "polyrun/quality/command"

RSpec.describe Polyrun::Quality::Command do
  def run_command(source, **options)
    described_class.call([Gem.ruby, "-e", source], root: Dir.pwd, timeout: 3, **options)
  end

  it "captures both streams, preserves status, and passes arguments literally" do
    result = described_class.call([Gem.ruby, "-e", 'puts ARGV.first; warn "problem"; exit 7', "$(touch impossible)"], root: Dir.pwd, timeout: 3)
    expect(result).to include("exitstatus" => 7, "stdout" => "$(touch impossible)\n", "stderr" => "problem\n")
    expect(result["wall_s"]).to be > 0
  end

  it "rejects nonfinite and nonpositive timeouts before spawning" do
    [0, -1, Float::NAN, Float::INFINITY].each do |timeout|
      expect { described_class.call([Gem.ruby], root: Dir.pwd, timeout: timeout) }.to raise_error(ArgumentError)
    end
  end

  it "closes input rather than waiting for terminal input" do
    expect(run_command("puts STDIN.read.inspect")["stdout"]).to eq("\"\"\n")
  end

  it "bounds output and terminates a writer" do
    result = run_command('loop { STDOUT.write("x" * 4096) }', max_output: 1000)
    expect(result["exitstatus"]).to eq(122)
    expect(result["stdout"].bytesize + result["stderr"].bytesize).to be <= 1000
  end

  it "times out a child and its descendant even when the leader exits first" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = described_class.call([Gem.ruby, "-e", "fork { sleep 20 }; exit!"], root: Dir.pwd, timeout: 0.2)
    expect(result["exitstatus"]).to eq(124)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
  end

  it "reports missing executables and signals as failures" do
    expect(described_class.call(["/missing-polyrun-command"], root: Dir.pwd, timeout: 1)["exitstatus"]).to eq(127)
    expect(run_command('Process.kill("TERM", Process.pid)')["exitstatus"]).to eq(143)
  end

  it "never interprets a single executable string through a shell" do
    Dir.mktmpdir do |root|
      result = described_class.call(["touch #{root}/unwanted"], root: root, timeout: 1)
      expect(result["exitstatus"]).to eq(127)
      expect(File.exist?(File.join(root, "unwanted"))).to be(false)
    end
  end

  it "keeps binary diagnostics serializable as valid UTF-8" do
    result = run_command('STDOUT.write([255].pack("C"))')
    expect { JSON.generate(result) }.not_to raise_error
  end

  it "closes an already opened pipe when a later descriptor allocation fails" do
    streams = nil
    attempts = 0
    allow(IO).to receive(:pipe).and_wrap_original do |original|
      attempts += 1
      raise Errno::EMFILE if attempts == 2

      streams = original.call
    end
    expect { run_command("exit") }.to raise_error(Errno::EMFILE)
    expect(streams).to all(be_closed)
  ensure
    streams&.each { |stream| stream.close unless stream.closed? }
  end
end
