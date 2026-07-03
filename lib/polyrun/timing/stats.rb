module Polyrun
  module Timing
    # Normalizes scalar or object timing entries for merge and binpack weight lookup.
    module Stats
      STAT_KEYS = %w[last_seconds min max mean p95 runs failures timeouts].freeze

      module_function

      def normalize_entry(value)
        case value
        when Hash
          normalize_hash(value)
        else
          sec = value.to_f
          {
            "last_seconds" => sec,
            "min" => sec,
            "max" => sec,
            "mean" => sec,
            "p95" => sec,
            "runs" => 1,
            "failures" => 0,
            "timeouts" => 0
          }
        end
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- timing hash key coercion
      def normalize_hash(h)
        out = {}
        sec = h["last_seconds"] || h[:last_seconds] || h["seconds"] || h[:seconds]
        sec = sec.to_f if sec
        mean = (h["mean"] || h[:mean] || sec)&.to_f
        out["last_seconds"] = (sec || mean || 0.0).to_f
        out["min"] = (h["min"] || h[:min] || out["last_seconds"]).to_f
        out["max"] = (h["max"] || h[:max] || out["last_seconds"]).to_f
        out["mean"] = (mean || out["last_seconds"]).to_f
        out["p95"] = (h["p95"] || h[:p95] || out["max"]).to_f
        out["runs"] = Integer(h["runs"] || h[:runs] || 1)
        out["failures"] = Integer(h["failures"] || h[:failures] || 0)
        out["timeouts"] = Integer(h["timeouts"] || h[:timeouts] || 0)
        out
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def binpack_weight(entry)
        h = normalize_entry(entry)
        h["last_seconds"].positive? ? h["last_seconds"] : h["mean"]
      end

      # rubocop:disable Metrics/AbcSize -- weighted mean merge
      def merge_entries(a, b)
        ha = normalize_entry(a)
        hb = normalize_entry(b)
        runs = ha["runs"] + hb["runs"]
        mean =
          if runs.positive?
            ((ha["mean"] * ha["runs"]) + (hb["mean"] * hb["runs"])) / runs.to_f
          else
            0.0
          end
        {
          "last_seconds" => [ha["last_seconds"], hb["last_seconds"]].max,
          "min" => [ha["min"], hb["min"]].min,
          "max" => [ha["max"], hb["max"]].max,
          "mean" => mean,
          "p95" => [ha["p95"], hb["p95"]].max,
          "runs" => runs,
          "failures" => ha["failures"] + hb["failures"],
          "timeouts" => ha["timeouts"] + hb["timeouts"]
        }
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
