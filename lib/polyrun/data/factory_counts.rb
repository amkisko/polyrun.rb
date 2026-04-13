module Polyrun
  module Data
    # Lightweight per-example factory/build counters with zero dependencies.
    # Call +reset!+ in +before(:suite)+ or +setup+, +record+ inside factory helpers, +summary+ in +after(:suite)+.
    module FactoryCounts
      class << self
        def reset!
          @counts = Hash.new(0)
        end

        def record(factory_name)
          @counts ||= Hash.new(0)
          @counts[factory_name.to_s] += 1
        end

        def counts
          @counts ||= Hash.new(0)
          @counts.dup
        end

        def summary_lines(top: 20)
          @counts ||= Hash.new(0)
          sorted = @counts.sort_by { |_, n| -n }
          sorted[0, top].map { |name, n| "  #{name}: #{n}" }
        end

        def format_summary(title: "Polyrun factory counts")
          lines = [title]
          lines.concat(summary_lines)
          lines.join("\n") + "\n"
        end
      end
    end
  end
end
