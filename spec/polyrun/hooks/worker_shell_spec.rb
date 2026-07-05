require "spec_helper"
require "polyrun/hooks"

RSpec.describe Polyrun::Hooks do
  describe "#build_worker_shell_script" do
    it "wraps the main command with before and after worker shell hooks" do
      hooks = described_class.new(
        "before_worker" => "echo before",
        "after_worker" => "echo after"
      )
      script = hooks.build_worker_shell_script(%w[ruby -e], %w[spec/a.rb])
      expect(script).to include("echo before")
      expect(script).to include("echo after")
      expect(script).to include("ruby -e spec/a.rb")
      expect(script).to include("exit $ec")
    end

    it "runs the main command when no worker hooks are configured" do
      hooks = described_class.new({})
      script = hooks.build_worker_shell_script(%w[true], [])
      expect(script).to include("true")
      expect(script).not_to include("WorkerRunner.run")
    end
  end
end
