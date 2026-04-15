module Polyrun
  class Config
    # Read nested keys from loaded YAML (+String+ / +Symbol+ indifferent at each step).
    module DottedPath
      module_function

      def dig(raw, dotted)
        segments = dotted.split(".")
        return nil if segments.empty?
        return nil if segments.any?(&:empty?)

        segments.reduce(raw) do |m, seg|
          break nil if m.nil?
          break nil unless m.is_a?(Hash)

          m[seg] || m[seg.to_sym]
        end
      end
    end
  end
end
