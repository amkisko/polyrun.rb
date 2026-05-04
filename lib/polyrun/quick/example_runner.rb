require_relative "../worker_ping"
require_relative "assertions"
require_relative "errors"
require_relative "matchers"

Polyrun::WorkerPing.ensure_interval_ping_thread!

module Polyrun
  module Quick
    # Per-example execution: merged lets, hooks, assertions, optional Capybara::DSL.
    class ExampleRunner
      include Assertions
      include Matchers

      def initialize(reporter)
        @reporter = reporter
        @_let_cache = {}
      end

      def run(group_name:, description:, ancestor_chain:, block:)
        @_let_cache = {}
        merge_lets_from_chain(ancestor_chain)
        define_let_methods!
        run_let_bangs_from_chain
        extend_capybara_if_enabled!
        qloc = quick_example_location(block)
        Polyrun::WorkerPing.ping!(location: qloc)
        begin
          run_before_hooks_from_chain(ancestor_chain)
          instance_eval(&block)
          @reporter.pass(group_name, description)
        rescue AssertionFailed => e
          @reporter.fail(group_name, description, e)
        rescue => e
          @reporter.error(group_name, description, e)
        ensure
          run_after_hooks_from_chain(ancestor_chain)
          reset_capybara_if_enabled!
          @_let_cache = {}
          Polyrun::WorkerPing.ping!(location: qloc)
        end
      end

      private

      def quick_example_location(block)
        loc = block&.source_location
        loc ? "#{loc[0]}:#{loc[1]}" : nil
      end

      def merge_lets_from_chain(ancestor_chain)
        @merged_lets = {}
        ancestor_chain.each do |g|
          @merged_lets.merge!(g.lets)
        end
        @let_bang_order = []
        ancestor_chain.each do |g|
          @let_bang_order.concat(g.let_bang_order)
        end
      end

      def define_let_methods!
        @merged_lets.each do |sym, proc|
          define_singleton_method(sym) do
            @_let_cache[sym] ||= instance_eval(&proc) # rubocop:disable ThreadSafety/ClassInstanceVariable -- per-example runner memo
          end
        end
      end

      def run_let_bangs_from_chain
        @let_bang_order.each { |sym| public_send(sym) }
      end

      def run_before_hooks_from_chain(ancestor_chain)
        ancestor_chain.each do |g|
          g.before_hooks.each { |h| instance_eval(&h) }
        end
      end

      def run_after_hooks_from_chain(ancestor_chain)
        ancestor_chain.reverse_each do |g|
          g.after_hooks.reverse_each { |h| instance_eval(&h) }
        end
      end

      def extend_capybara_if_enabled!
        return unless Quick.capybara?
        return unless defined?(::Capybara)
        return unless defined?(::Capybara::DSL)

        extend ::Capybara::DSL
      end

      def reset_capybara_if_enabled!
        return unless Quick.capybara?
        return unless defined?(::Capybara)

        ::Capybara.reset_sessions!
      rescue
        # Driver/session may be absent in non-Capybara runs
      end
    end
  end
end
