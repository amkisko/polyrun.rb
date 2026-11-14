require "digest"
require "fileutils"
require "find"
require "json"
require "tempfile"
require_relative "error"
require_relative "../config/tools"

module Polyrun
  module Graph
    class Workspace
      STATE = Config::ToolDefaults::GRAPH.fetch("state_dir")
      attr_reader :root, :settings

      def state
        @settings.fetch("state_dir", STATE)
      end

      def initialize(root, settings: {})
        @settings = Config::Tools.runtime("graph", settings)
        @root = File.realpath(root)
      end

      def path(relative, base: @root)
        parts = relative.is_a?(String) ? relative.split("/", -1) : []
        if parts.empty? || parts.any? { |part| part.empty? || part == "." || part == ".." || part.include?("\0") }
          raise Error.new("INVALID_PLAN", "invalid project path")
        end
        parts.reduce(base) do |parent, part|
          result = File.join(parent, part)
          raise Error.new("INVALID_PLAN", "symbolic link in project path") if File.symlink?(result)

          result
        end
      end

      def files
        found = source_directories.flat_map { |directory| source_files(directory) }.uniq.sort
        raise Error.new("RESOURCE_LIMIT", "too many source files") if found.size > @settings["max_source_files"]

        found
      end

      def hashes
        total = 0
        files.to_h do |relative|
          absolute = path(relative)
          total += File.size(absolute)
          raise Error.new("RESOURCE_LIMIT", "source file is too large") if File.size(absolute) > @settings["max_source_file_bytes"]
          raise Error.new("RESOURCE_LIMIT", "source tree exceeds configured byte limit") if total > @settings["max_source_bytes"]

          [relative, Digest::SHA256.file(absolute).hexdigest]
        end
      end

      def snapshot(hashes)
        "snapshot-#{Digest::SHA256.hexdigest(JSON.generate(hashes))}"
      end

      def read_json(relative, limit: @settings["max_artifact_bytes"])
        file = path(relative)
        raise Error.new("MISSING_STATE", "graph state missing; run polyrun graph index") unless File.file?(file)
        raise Error.new("RESOURCE_LIMIT", "graph state is too large") if File.size(file) > limit

        JSON.parse(File.binread(file))
      rescue JSON::ParserError
        raise Error.new("INVALID_PLAN", "invalid graph data")
      end

      def write_json(relative, value, limit: @settings["max_artifact_bytes"])
        destination = path(relative)
        payload = JSON.generate(value)
        raise Error.new("RESOURCE_LIMIT", "graph state is too large") if payload.bytesize > limit

        FileUtils.mkdir_p(File.dirname(destination))
        Tempfile.create("polyrun-graph", File.dirname(destination)) do |file|
          file.write(payload)
          file.flush
          file.fsync
          File.rename(file.path, destination)
        end
        value
      end

      private

      def source_directories
        roots = @settings["source_roots"].map { |name| (name == ".") ? @root : path(name) }.select { |directory| File.directory?(directory) }
        roots = [@root] if roots.empty? && @settings["source_fallback"]
        roots
      end

      def source_files(directory)
        found = []
        Find.find(directory) do |entry|
          relative = entry.delete_prefix("#{@root}/")
          if entry != directory && (relative == state || excluded?(relative))
            Find.prune if File.directory?(entry)
            next
          end
          if File.symlink?(entry)
            raise Error.new("INVALID_PLAN", "symbolic link in source tree")
          elsif File.file?(entry) && entry.end_with?(".rb")
            found << relative
            raise Error.new("RESOURCE_LIMIT", "too many source files") if found.length > @settings["max_source_files"]
          end
        end
        found
      end

      def excluded?(relative)
        name = File.basename(relative)
        name.start_with?(".") || @settings["source_exclude"].any? { |pattern| File.fnmatch?(pattern, name) || File.fnmatch?(pattern, relative, File::FNM_PATHNAME) }
      end
    end
  end
end
