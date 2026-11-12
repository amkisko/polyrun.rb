module Polyrun
  module Quick
    # Predicate-style matchers (+be ==+, +be_a+, +raise_exception+) for Quick expectations.
    module MatchersPredicates
      def be
        BeMatcher.new
      end

      def be_a(klass)
        BeAMatcher.new(klass)
      end

      alias_method :be_kind_of, :be_a

      def raise_exception(exception_class = StandardError, message: nil)
        RaiseExceptionMatcher.new(exception_class, message: message)
      end
    end

    class BeMatcher
      def ==(other)
        EqMatcher.new(other)
      end

      def >(other)
        CompareMatcher.new(:>, other)
      end

      def >=(other)
        CompareMatcher.new(:>=, other)
      end

      def <(other)
        CompareMatcher.new(:<, other)
      end

      def <=(other)
        CompareMatcher.new(:<=, other)
      end
    end

    class CompareMatcher
      def initialize(op, expected)
        @op = op
        @expected = expected
      end

      def matches?(actual)
        actual.public_send(@op, @expected)
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected #{actual.inspect} #{@op} #{@expected.inspect}"
      end

      def failure_message_when_negated(actual)
        "expected #{actual.inspect} not #{@op} #{@expected.inspect}"
      end
    end

    class BeAMatcher
      def initialize(klass)
        @klass = klass
      end

      def matches?(actual)
        actual.is_a?(@klass)
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected #{actual.inspect} to be a #{@klass}"
      end

      def failure_message_when_negated(actual)
        "expected #{actual.inspect} not to be a #{@klass}"
      end
    end

    class RaiseExceptionMatcher
      def initialize(exception_class, message: nil)
        @exception_class = exception_class
        @message = message
      end

      def matches?(actual)
        return false unless actual.respond_to?(:call)

        begin
          actual.call
          false
        rescue @exception_class => e
          return true if @message.nil?
          return true if @message.is_a?(Regexp) && @message.match?(e.message)

          e.message == @message.to_s
        rescue
          false
        end
      end

      def does_not_match?(actual)
        !matches?(actual)
      end

      def failure_message(actual)
        "expected block to raise #{@exception_class}"
      end

      def failure_message_when_negated(actual)
        "expected block not to raise #{@exception_class}"
      end
    end
  end
end
