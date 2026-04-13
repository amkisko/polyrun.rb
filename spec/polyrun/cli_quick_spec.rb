require "spec_helper"

RSpec.describe "CLI quick" do
  it "runs polyrun quick with a temp file" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "q.rb")
      File.write(f, <<~RUBY)
        describe "cli" do
          it "ok" do
            assert true
          end
        end
      RUBY

      code = Polyrun::CLI.run(["quick", f])
      expect(code).to eq(0)
    end
  end
end
