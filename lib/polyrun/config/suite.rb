require_relative "tools"

module Polyrun
  class Config
    # Applies a named +suites:+ overlay onto a loaded polyrun.yml hash.
    module Suite
      PARTITION_KEYS = %w[
        paths_file shard_total shard_index strategy seed timing_file timing_granularity
        constraints constraints_file shard_weights suite paths_build shard_processes
        shard_workers workers_per_shard
      ].freeze

      TOP_MERGE_KEYS = (%w[prepare start hooks reporting coverage databases graph mutation quality] + ToolDefaults::SHARED.keys).freeze

      module_function

      def merge(raw, suite_name)
        name = suite_name.to_s.strip
        base = deep_stringify(raw.is_a?(Hash) ? raw : {})
        return [base, nil] if name.empty?

        suites = base["suites"]
        unless suites.is_a?(Hash)
          raise Polyrun::Error, "polyrun: suites: map is required when selecting suite #{name.inspect}"
        end

        overlay = suites[name]
        unless overlay.is_a?(Hash)
          available = suites.keys.map(&:to_s).sort.join(", ")
          raise Polyrun::Error, "polyrun: unknown suite #{name.inspect} (known: #{available})"
        end

        apply_overlay!(base, deep_stringify(overlay))
        [base, name]
      end

      def apply_overlay!(base, overlay)
        errors = Tools.validate(overlay)
        raise Polyrun::Error, errors.join("; ") unless errors.empty?

        merge_partition_block!(base, overlay)
        merge_partition_shortcuts!(base, overlay)
        merge_top_keys!(base, overlay)
      end
      private_class_method :apply_overlay!

      def merge_partition_block!(base, overlay)
        return unless overlay["partition"].is_a?(Hash)

        base["partition"] = deep_merge_hashes(base["partition"] || {}, overlay["partition"])
      end
      private_class_method :merge_partition_block!

      def merge_partition_shortcuts!(base, overlay)
        PARTITION_KEYS.each do |key|
          next unless overlay.key?(key)

          base["partition"] ||= {}
          base["partition"][key] =
            if key == "paths_build" && base["partition"][key].is_a?(Hash) && overlay[key].is_a?(Hash)
              deep_merge_hashes(base["partition"][key], overlay[key])
            else
              overlay[key]
            end
        end
      end
      private_class_method :merge_partition_shortcuts!

      def merge_top_keys!(base, overlay)
        TOP_MERGE_KEYS.each do |key|
          next unless overlay.key?(key)

          base[key] =
            if base[key].is_a?(Hash) && overlay[key].is_a?(Hash)
              deep_merge_hashes(base[key], overlay[key])
            else
              overlay[key]
            end
        end
      end
      private_class_method :merge_top_keys!

      def deep_stringify(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), out| out[k.to_s] = deep_stringify(v) }
        when Array
          obj.map { |e| deep_stringify(e) }
        else
          obj
        end
      end
      private_class_method :deep_stringify

      def deep_merge_hashes(base, overlay)
        a = base.dup
        overlay.each do |k, v|
          a[k] = if a[k].is_a?(Hash) && v.is_a?(Hash)
            deep_merge_hashes(a[k], v)
          else
            v
          end
        end
        a
      end
      private_class_method :deep_merge_hashes
    end
  end
end
