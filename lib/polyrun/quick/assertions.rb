require_relative "errors"

module Polyrun
  module Quick
    module Assertions
      def assert(condition, message = "assertion failed")
        raise AssertionFailed, message unless condition
      end

      def assert_equal(expected, actual, message = nil)
        return if expected == actual

        raise AssertionFailed,
          message || "expected #{expected.inspect}, got #{actual.inspect}"
      end

      def assert_nil(obj, message = nil)
        return if obj.nil?

        raise AssertionFailed, message || "expected nil, got #{obj.inspect}"
      end

      def assert_raises(exception_class = StandardError)
        yield
      rescue exception_class
        nil
      else
        raise AssertionFailed, "expected #{exception_class} to be raised"
      end
    end
  end
end
