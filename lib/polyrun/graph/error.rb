module Polyrun
  module Graph
    class Error < StandardError
      attr_reader :code, :exitstatus

      def initialize(code, message, exitstatus: 1)
        @code = code
        @exitstatus = exitstatus
        super(message)
      end
    end
  end
end
