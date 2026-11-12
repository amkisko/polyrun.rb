require "spec_helper"
require "fileutils"
require "polyrun/quick"
require "tmpdir"
require "stringio"

RSpec.describe "Polyrun::Quick config and integrations" do
  it "adds load paths from config/polyrun_quick.rb" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.mkdir_p(File.join(dir, "fixtures"))
      File.write(File.join(dir, "fixtures", "sample_helper.rb"), "module SampleHelper; VALUE = 7; end\n")
      File.write(File.join(dir, "config", "polyrun_quick.rb"), <<~RUBY)
        add_load_path "fixtures"
      RUBY
      f = File.join(dir, "load.rb")
      File.write(f, <<~RUBY)
        require "sample_helper"
        describe "g" do
          it "a" do
            assert_equal 7, SampleHelper::VALUE
          end
        end
      RUBY

      with_chdir(dir) do
        code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
        expect(code).to eq(0)
      end
    end
  end

  it "loads config/polyrun_quick.rb suite hooks" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "polyrun_quick.rb"), <<~RUBY)
        before_suite { Thread.current[:polyrun_quick_suite] = :before }
        after_suite { |status| Thread.current[:polyrun_quick_suite_status] = status }
      RUBY
      f = File.join(dir, "ok.rb")
      File.write(f, <<~RUBY)
        describe "g" do
          it "a" do
            assert_equal :before, Thread.current[:polyrun_quick_suite]
          end
        end
      RUBY

      Thread.current[:polyrun_quick_suite] = nil
      Thread.current[:polyrun_quick_suite_status] = nil
      with_chdir(dir) do
        code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
        expect(code).to eq(0)
      end
      expect(Thread.current[:polyrun_quick_suite_status]).to eq(0)
    end
  end

  it "extends Capybara::DSL when capybara! and Capybara are defined" do
    capybara = Module.new
    dsl = Module.new do
      def visit(path)
        @visited = path
      end

      attr_reader :visited
    end
    capybara.const_set(:DSL, dsl)
    capybara.define_singleton_method(:reset_sessions!) { nil }

    stub_const("Capybara", capybara)

    Dir.mktmpdir do |dir|
      f = File.join(dir, "cap.rb")
      File.write(f, <<~RUBY)
        Polyrun::Quick.capybara!
        describe "ui" do
          it "visits" do
            visit("/")
            assert_equal "/", @visited
          end
        end
      RUBY

      code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(code).to eq(0)
    end
  end
end
