require "digest/md5"
require "fileutils"
require_relative "../process_stdio"

module Polyrun
  module Prepare
    # Asset digest and optional Rails +assets:precompile+, stdlib only.
    module Assets
      module_function

      # Stable digest of a list of files (sorted). Directories are expanded to all files recursively.
      def digest_sources(*paths)
        files = []
        paths.flatten.compact.each do |p|
          next unless p

          path = p.to_s
          if File.directory?(path)
            Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH).each do |f|
              files << f if File.file?(f)
            end
          elsif File.file?(path)
            files << path
          end
        end
        files.sort!
        combined = files.map { |f| "#{f}:#{Digest::MD5.file(f).hexdigest}" }.join("|")
        Digest::MD5.hexdigest(combined)
      end

      # Writes digest to +marker_path+ if missing or content differs (caller runs compile when needed).
      def stale?(marker_path, *digest_paths)
        return true unless File.file?(marker_path)

        File.read(marker_path).strip != digest_sources(*digest_paths)
      end

      def write_marker!(marker_path, *digest_paths)
        FileUtils.mkdir_p(File.dirname(marker_path))
        File.write(marker_path, digest_sources(*digest_paths))
      end

      # Shells out to +bin/rails assets:precompile+ when +rails_root+ contains +bin/rails+.
      # +silent: true+ discards child stdio (+File::NULL+); +silent: false+ inherits the terminal.
      def precompile!(rails_root:, silent: true)
        exe = File.join(rails_root, "bin", "rails")
        raise Polyrun::Error, "Prepare::Assets: no #{exe}" unless File.executable?(exe)

        st, out, err = Polyrun::ProcessStdio.spawn_wait(
          nil,
          exe,
          "assets:precompile",
          chdir: rails_root,
          silent: silent
        )
        unless st.success?
          raise Polyrun::Error, Polyrun::ProcessStdio.format_failure_message("assets:precompile", st, out, err)
        end

        true
      end
    end
  end
end
