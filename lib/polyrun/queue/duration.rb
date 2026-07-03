require "json"
require "optparse"
require "shellwords"

module Polyrun
  module Queue
    # Parse duration strings like 10m, 1h, 600s into seconds.
    module Duration
      module_function

      def parse_seconds(text)
        s = text.to_s.strip
        return Float(s) if s.match?(/\A\d+(\.\d+)?\z/)

        m = s.match(/\A(\d+(?:\.\d+)?)(s|m|h|d)\z/i)
        raise Polyrun::Error, "invalid duration: #{text.inspect}" unless m

        val = Float(m[1])
        case m[2].downcase
        when "s" then val
        when "m" then val * 60
        when "h" then val * 3600
        when "d" then val * 86_400
        else
          raise Polyrun::Error, "invalid duration: #{text.inspect}"
        end
      end
    end
  end
end
