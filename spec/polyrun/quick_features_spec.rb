require "spec_helper"
require "fileutils"
require "polyrun/quick"
require "tmpdir"
require "stringio"

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

  it "passes the failure into after hooks" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "after_err.rb")
      File.write(f, <<~RUBY)
        describe "x" do
          after do |error|
            Thread.current[:polyrun_quick_after_error] = error
          end
          it "fails" do
            assert_equal 1, 2
          end
        end
      RUBY

      Thread.current[:polyrun_quick_after_error] = :unset
      Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(Thread.current[:polyrun_quick_after_error]).to be_a(Polyrun::Quick::AssertionFailed)
    end
  end

  it "runs around hooks and requires run.call" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "around.rb")
      File.write(f, <<~RUBY)
        describe "x" do
          around do |run|
            Thread.current[:polyrun_quick_around] = :enter
            run.call
            Thread.current[:polyrun_quick_around] = :exit
          end
          it "ok" do
            assert_equal :enter, Thread.current[:polyrun_quick_around]
          end
        end
      RUBY

      Thread.current[:polyrun_quick_around] = nil
      code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(code).to eq(0)
      expect(Thread.current[:polyrun_quick_around]).to eq(:exit)
    end
  end

  it "fails when around skips run.call" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "around_skip.rb")
      File.write(f, <<~RUBY)
        describe "x" do
          around { |_run| nil }
          it "never" do
            assert_equal 1, 1
          end
        end
      RUBY

      err = StringIO.new
      code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: err)
      expect(code).to eq(1)
      expect(err.string).to include("around hook did not run")
    end
  end

  it "supports with, subject, be predicates, and raise_exception" do
    Dir.mktmpdir do |dir|
      f = File.join(dir, "dsl.rb")
      File.write(f, <<~RUBY)
        describe String do
          with "empty" do
            subject { "" }
            it "is a String" do
              expect(subject).to be_a(String)
              expect(subject.length).to be == 0
            end
          end

          it "raises" do
            expect { raise ArgumentError, "nope" }.to raise_exception(ArgumentError)
          end
        end
      RUBY

      code = Polyrun::Quick::Runner.run(paths: [f], out: StringIO.new, err: StringIO.new)
      expect(code).to eq(0)
    end
  end
end
