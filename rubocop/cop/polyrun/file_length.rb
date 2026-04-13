module RuboCop
  module Cop
    module Polyrun
      # Enforces a maximum line count per Ruby source file (blank lines and comments count).
      # RuboCop core does not ship Metrics/FileLength; this cop fills that gap.
      class FileLength < Base
        MSG = "File has too many lines (%<current>d/%<max>d)."

        def on_new_investigation
          super

          max = cop_config["Max"]
          return if max.nil?

          current = processed_source.lines.count
          return if current <= max

          add_global_offense(format(MSG, current: current, max: max))
        end
      end
    end
  end
end
