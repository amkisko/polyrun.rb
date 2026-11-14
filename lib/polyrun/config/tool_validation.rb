require_relative "tool_defaults"

module Polyrun
  class Config
    module ToolValidation
      OPTIONAL_STRINGS = %w[root output subjects_file plan].freeze
      COUNTS = %w[min_line_churn min_query_count hot_line_example_overlap minimum_unique_lines_per_example max_zero_hit_examples max_hot_line_overlap].freeze

      module_function

      def check(value, defaults, prefix)
        return ["#{prefix} must be a mapping"] unless value.is_a?(Hash)

        value.flat_map do |key, item|
          path = "#{prefix}.#{key}"
          next ["unknown setting #{path}"] unless defaults.key?(key)
          expected = defaults[key]
          if expected.is_a?(Hash)
            (key == "ceilings") ? check_ceilings(item, path) : check(item, expected, path)
          elsif valid?(key, item, expected)
            []
          else
            ["invalid setting #{path}"]
          end
        end
      end

      def valid?(key, value, expected)
        return value.nil? || valid_string?(value) if OPTIONAL_STRINGS.include?(key)
        return value.is_a?(Numeric) && value.finite? && value.positive? if key == "timeout"
        return relative_path?(value) if key == "state_dir"
        return valid_count?(value, expected) if COUNTS.include?(key)
        return value.nil? || nonnegative?(value) if expected.nil?
        return positive_integer?(value) if expected.is_a?(Integer)
        return nonnegative?(value) && value <= 1 if key == "sample"
        return value == true || value == false if expected == true || expected == false
        return valid_array?(key, value) if expected.is_a?(Array)

        valid_string?(value)
      end

      def positive_integer?(value)
        value.is_a?(Integer) && value.positive?
      end

      def valid_count?(value, expected)
        (expected.nil? && value.nil?) || (value.is_a?(Integer) && value >= 0)
      end

      def valid_string?(value)
        value.is_a?(String) && !value.empty? && !value.include?("\0")
      end

      def nonnegative?(value)
        value.is_a?(Numeric) && value.finite? && value >= 0
      end

      def valid_array?(key, value)
        return false unless value.is_a?(Array) && value.all? { |entry| valid_string?(entry) }
        return !value.empty? && (value - %w[literal operator body]).empty? if key == "operators"
        return value.all? { |entry| relative_path?(entry) || entry == "." } if key == "source_roots"

        true
      end

      def relative_path?(value)
        value.is_a?(String) && !value.empty? && !value.include?("\0") && !value.split("/", -1).any? { |part| ["", ".", ".."].include?(part) }
      end

      def check_ceilings(value, prefix)
        return ["#{prefix} must be a mapping"] unless value.is_a?(Hash)

        value.filter_map do |key, item|
          "invalid setting #{prefix}.#{key}" unless item.is_a?(Numeric) && item.finite? && item >= 0
        end
      end
    end
  end
end
