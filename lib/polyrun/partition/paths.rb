module Polyrun
  module Partition
    # Shared spec path listing for run-shards, queue init, and plan helpers.
    module Paths
      module_function

      def read_lines(path)
        File.read(File.expand_path(path.to_s, Dir.pwd)).split("\n").map(&:strip).reject(&:empty?)
      end

      # When +paths_file+ is set but missing, returns +{ error: "..." }+.
      # Otherwise returns +{ items:, source: }+ (human-readable source label).
      def resolve_run_shard_items(paths_file: nil, cwd: Dir.pwd)
        if paths_file
          abs = File.expand_path(paths_file.to_s, cwd)
          unless File.file?(abs)
            return {error: "paths file not found: #{abs}"}
          end
          {items: read_lines(abs), source: paths_file.to_s}
        elsif File.file?(File.join(cwd, "spec", "spec_paths.txt"))
          {items: read_lines(File.join(cwd, "spec", "spec_paths.txt")), source: "spec/spec_paths.txt"}
        else
          {items: Dir.glob(File.join(cwd, "spec/**/*_spec.rb")).sort, source: "spec/**/*_spec.rb glob"}
        end
      end
    end
  end
end
