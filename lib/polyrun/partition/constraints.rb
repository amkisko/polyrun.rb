module Polyrun
  module Partition
    # Hard constraints for plan assignment (spec_queue.md): pins, serial globs.
    # Pins win over serial_glob. First matching pin glob wins.
    class Constraints
      attr_reader :pin_map, :serial_globs, :serial_shard

      # @param pin_map [Hash{String=>Integer}] glob or exact path => shard index
      # @param serial_globs [Array<String>] fnmatch patterns forced to +serial_shard+ (default 0) unless pinned
      # @param root [String] project root for expanding relative paths
      def initialize(pin_map: {}, serial_globs: [], serial_shard: 0, root: nil)
        @pin_map = pin_map.transform_keys(&:to_s).transform_values { |v| Integer(v) }
        @serial_globs = Array(serial_globs).map(&:to_s)
        @serial_shard = Integer(serial_shard)
        @root = root ? File.expand_path(root) : Dir.pwd
      end

      def self.from_hash(h, root: nil)
        h = h.transform_keys(&:to_s) if h.is_a?(Hash)
        return new(root: root) unless h.is_a?(Hash)

        pins = h["pin"] || h["pins"] || {}
        serial = h["serial_glob"] || h["serial_globs"] || []
        serial_shard = h["serial_shard"] || 0
        new(
          pin_map: pins.is_a?(Hash) ? pins : {},
          serial_globs: serial.is_a?(Array) ? serial : [],
          serial_shard: serial_shard,
          root: root
        )
      end

      # Returns Integer shard index if constrained, or nil if free to place by LPT/HRW.
      def forced_shard_for(path)
        rel = path.to_s
        abs = File.expand_path(rel, @root)

        @pin_map.each do |pattern, shard|
          next if pattern.to_s.empty?

          if match_pattern?(pattern.to_s, rel, abs)
            return shard
          end
        end

        @serial_globs.each do |g|
          if match_pattern?(g, rel, abs)
            return @serial_shard
          end
        end

        nil
      end

      def any?
        @pin_map.any? || @serial_globs.any?
      end

      private

      def match_pattern?(pattern, rel, abs)
        p = pattern.to_s
        File.fnmatch?(p, rel, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
          File.fnmatch?(p, abs, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
          p == rel || p == abs
      end
    end
  end
end
