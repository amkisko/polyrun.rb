module Polyrun
  module Coverage
    module ExampleDiff
      # Path inclusion for scoped snapshots and track-aware diffs.
      class TrackFilter
        def initialize(root:, track_under: nil, ignore_paths: [])
          @root = root ? File.expand_path(root) : nil
          @track_under = Array(track_under).map(&:to_s).reject(&:empty?)
          @ignore = Array(ignore_paths).map(&:to_s).reject(&:empty?)
          @prefixes =
            if @root && !@track_under.empty?
              @track_under.map { |directory| File.join(@root, directory) }
            else
              []
            end
        end

        def include_path?(path)
          absolute = absolute_path(path)
          return false if ignored?(absolute)

          return true if @prefixes.empty?

          @prefixes.any? { |prefix| absolute == prefix || absolute.start_with?(prefix + "/") }
        end

        private

        def absolute_path(path)
          if @root
            File.expand_path(path.to_s, @root)
          else
            File.expand_path(path.to_s)
          end
        end

        def ignored?(absolute)
          @ignore.any? { |pattern| path_matches_ignore?(absolute, pattern) }
        end

        def path_matches_ignore?(path, pattern)
          return path.include?(pattern) if !pattern.start_with?("/")

          path.match?(Regexp.new(pattern))
        rescue RegexpError
          path.include?(pattern)
        end
      end
    end
  end
end
