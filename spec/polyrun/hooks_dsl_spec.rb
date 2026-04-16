require "spec_helper"

RSpec.describe "Polyrun::Hooks Ruby DSL" do
  around do |example|
    Polyrun::Hooks::Dsl.clear_cache!
    example.run
    Polyrun::Hooks::Dsl.clear_cache!
  end

  it "runs before(:suite) blocks from hooks.ruby" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        hook_rb = File.join(dir, "my_hooks.rb")
        File.write(hook_rb, <<~RUBY)
          before(:suite) { |env| File.write("dsl_out.txt", env.fetch("POLYRUN_HOOK_PHASE")) }
        RUBY
        File.write("polyrun.yml", <<~YAML)
          hooks:
            ruby: my_hooks.rb
        YAML

        h = Polyrun::Hooks.from_config(Polyrun::Config.load(path: File.join(dir, "polyrun.yml")))
        code = h.run_phase(:before_suite, ENV.to_h)
        expect(code).to eq(0)
        expect(File.read("dsl_out.txt")).to eq("before_suite")
      end
    end
  end

  it "runs Ruby before shell for the same phase" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write(File.join(dir, "h.rb"), <<~RUBY)
          before(:suite) { File.write("order.txt", "ruby") }
        RUBY
        h = Polyrun::Hooks.new(
          "ruby" => "h.rb",
          "before_suite" => "printf shell >> order.txt"
        )
        h.run_phase(:before_suite, ENV.to_h)
        expect(File.read(File.join(dir, "order.txt"))).to eq("rubyshell")
      end
    end
  end

  it "includes worker runner line when before(:each) is defined" do
    Dir.mktmpdir do |dir|
      with_chdir(dir) do
        File.write(File.join(dir, "w.rb"), <<~RUBY)
          before(:each) { }
        RUBY
        h = Polyrun::Hooks.new("ruby" => "w.rb")
        script = h.build_worker_shell_script(%w[bundle exec rspec], %w[spec/x_spec.rb])
        expect(script).to include("WorkerRunner.run")
        expect(script).to include("before_worker")
        expect(script).to include("bundle exec rspec spec/x_spec.rb")
      end
    end
  end
end
