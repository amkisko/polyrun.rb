require "spec_helper"
require "polyrun/quick"
require "tmpdir"

RSpec.describe "Polyrun::Quick DSL" do
  it "runs nested describe with before and let" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "nest.rb")
      File.write(f, <<~RUBY)
        describe "outer" do
          before { @x = 1 }
          let(:y) { @x + 1 }

          describe "inner" do
            it "sees let and before" do
              assert_equal 1, @x
              assert_equal 2, y
            end
          end
        end
      RUBY

      code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(code).to eq(0)
    end
  end

  it "supports test alias and expect().to matchers" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "exp.rb")
      File.write(f, <<~RUBY)
        describe "m" do
          test "synonym" do
            expect(1 + 1).to eq(2)
            expect(nil).to be_falsey
            expect("ab").to match(/a/)
            expect([1, 2]).to include(1, 2)
          end
        end
      RUBY

      code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(code).to eq(0)
    end
  end

  it "runs after hooks on failure" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "after.rb")
      File.write(f, <<~RUBY)
        describe "x" do
          after { Thread.current[:polyrun_quick_after] = true }
          it "fails" do
            assert_equal 1, 2
          end
        end
      RUBY

      Thread.current[:polyrun_quick_after] = false
      Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(Thread.current[:polyrun_quick_after]).to be true
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
