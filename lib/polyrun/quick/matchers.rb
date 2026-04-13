require_relative "errors"

module Polyrun
  module Quick
    # Minimal +expect(x).to …+ chain (RSpec-ish) without RSpec.
    class Expectation
      def initialize(actual)
        @actual = actual
      end

      def to(matcher)
        return if matcher.matches?(@actual)

        raise AssertionFailed, matcher.failure_message(@actual)
      end

      def not_to(matcher)
        return if matcher.does_not_match?(@actual)

        raise AssertionFailed, matcher.failure_message_when_negated(@actual)
      end
    end

    module Matchers
      def expect(actual)
        Expectation.new(actual)
      end

      def eq(expected)
        EqMatcher.new(expected)
      end

      def be_truthy
        TruthyMatcher.new
      end

      def be_falsey
        FalseyMatcher.new
      end

      def include(*expected)
        IncludeMatcher.new(expected)
      end

      def match(pattern)
        RegexMatcher.new(pattern)
      end
    end

    class EqMatcher
      def initialize(expected)
        @expected = expected
      end

      def matches?(actual)
        @expected == actual
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected #{@expected.inspect}, got #{actual.inspect}"
      end

      def failure_message_when_negated(actual)
        "expected #{actual.inspect} not to eq #{@expected.inspect}"
      end
    end

    class TruthyMatcher
      def matches?(actual)
        !!actual
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected truthy, got #{actual.inspect}"
      end

      def failure_message_when_negated(actual)
        "expected falsey, got #{actual.inspect}"
      end
    end

    class FalseyMatcher
      def matches?(actual)
        !actual
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected falsey, got #{actual.inspect}"
      end

      def failure_message_when_negated(actual)
        "expected truthy, got #{actual.inspect}"
      end
    end

    class IncludeMatcher
      def initialize(expected_parts)
        @expected_parts = expected_parts
      end

      def matches?(actual)
        return false unless actual.respond_to?(:include?)

        @expected_parts.all? { |part| actual.include?(part) }
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected #{actual.inspect} to include #{@expected_parts.map(&:inspect).join(", ")}"
      end

      def failure_message_when_negated(actual)
        "expected #{actual.inspect} not to include #{@expected_parts.map(&:inspect).join(", ")}"
      end
    end

    class RegexMatcher
      def initialize(pattern)
        @pattern = pattern
      end

      def matches?(actual)
        return false unless actual.respond_to?(:to_s)

        @pattern === actual.to_s
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected #{actual.inspect} to match #{@pattern.inspect}"
      end

      def failure_message_when_negated(actual)
        "expected #{actual.inspect} not to match #{@pattern.inspect}"
      end
    end
  end
end
