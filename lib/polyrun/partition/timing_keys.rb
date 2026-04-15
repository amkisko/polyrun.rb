require "json"

require_relative "../log"

module Polyrun
  module Partition
    # Normalizes partition item keys and timing JSON keys for +file+ vs experimental +example+ granularity.
    #
    # * +file+ — one item per spec file; keys are absolute paths (see {#canonical_file_path}).
    # * +example+ — one item per example (RSpec-style +path:line+); keys are +"#{absolute_path}:#{line}+".
    module TimingKeys
      module_function

      # Resolves the parent directory with +File.realpath+ so +/var/...+ and +/private/var/...+ (macOS
      # tmpdirs) and symlink segments map to one key for the same file.
      def canonical_file_path(abs_path)
        dir = File.dirname(abs_path)
        base = File.basename(abs_path)
        File.join(File.realpath(dir), base)
      rescue SystemCallError
        abs_path
      end

      # @return [:file, :example]
      def normalize_granularity(value)
        case value.to_s.strip.downcase
        when "example", "examples"
          :example
        else
          :file
        end
      end

      # File path only (for partition constraints) when +item+ is +path:line+.
      def file_part_for_constraint(item)
        s = item.to_s
        m = s.match(/\A(.+):(\d+)\z/)
        return nil unless m && m[2].match?(/\A\d+\z/)

        m[1]
      end

      # Normalize a path or +path:line+ locator relative to +root+ for cost maps and +Plan+ items.
      def normalize_locator(raw, root, granularity)
        s = raw.to_s.strip
        return canonical_file_path(File.expand_path(s, root)) if s.empty?

        if granularity == :example && (m = s.match(/\A(.+):(\d+)\z/)) && m[2].match?(/\A\d+\z/)
          fp = canonical_file_path(File.expand_path(m[1], root))
          return "#{fp}:#{m[2]}"
        end

        canonical_file_path(File.expand_path(s, root))
      end

      # Loads merged timing JSON (+path => seconds+ or +path:line => seconds+).
      #
      # @param root [String, nil] directory for normalizing relative keys (default: +Dir.pwd+). Use the
      #   same working directory (or pass the same +root+ as {Partition::Plan}+'s +root+) as when
      #   generating the timing file so keys align.
      def load_costs_json_file(path, granularity, root: nil)
        abs = File.expand_path(path.to_s, Dir.pwd)
        return {} unless File.file?(abs)

        data = JSON.parse(File.read(abs))
        return {} unless data.is_a?(Hash)

        g = normalize_granularity(granularity)
        root = File.expand_path(root || Dir.pwd)
        out = {}
        data.each do |k, v|
          key = normalize_locator(k.to_s, root, g)
          fv = v.to_f
          if out.key?(key) && out[key] != fv
            Polyrun::Log.warn(
              "polyrun: timing JSON duplicate key #{key.inspect} after normalize (#{out[key]} vs #{fv}); using #{fv}"
            )
          end
          out[key] = fv
        end
        out
      end
    end
  end
end
