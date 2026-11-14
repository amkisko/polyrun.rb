require "digest"
require "fileutils"
require "find"
require_relative "../config/tools"

module Polyrun
  module Quality
    class Sandbox
      attr_reader :bytes

      def initialize(root, settings: {})
        @settings = Config::Tools.merge(Config::ToolDefaults::STAGING, Config::Tools.stringify(settings))
        errors = Config::ToolValidation.check(@settings, Config::ToolDefaults::STAGING, "staging")
        raise ArgumentError, errors.join("; ") unless errors.empty?

        @root = File.realpath(root)
        @bytes = 0
        @files = inventory
      end

      def copy_to(destination)
        @files.each do |relative, expected|
          source = File.join(@root, relative)
          raise ArgumentError, "project changed while staging" unless File.file?(source) && !File.symlink?(source) && Digest::SHA256.file(source).hexdigest == expected

          target = File.join(destination, relative)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.copy_file(source, target, true)
          raise ArgumentError, "project changed while staging" unless Digest::SHA256.file(target).hexdigest == expected
        end
        destination
      end

      def self.environment(destination)
        {"BUNDLE_GEMFILE" => File.file?(File.join(destination, "Gemfile")) ? File.join(destination, "Gemfile") : nil,
         "RUBYLIB" => [File.join(destination, "lib"), ENV["RUBYLIB"]].compact.join(File::PATH_SEPARATOR)}
      end

      private

      def inventory
        files = {}
        Find.find(@root) do |path|
          next if path == @root

          name = File.basename(path)
          relative = path.delete_prefix("#{@root}/")
          if excluded?(name) || @settings["exclude_paths"].any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME) }
            Find.prune if File.directory?(path)
            next
          end
          raise ArgumentError, "symbolic links are not supported in staged projects" if File.symlink?(path)
          next unless File.file?(path)

          @bytes += File.size(path)
          raise ArgumentError, "staged project exceeds configured file or byte limit" if @bytes > @settings["max_bytes"] || files.size >= @settings["max_files"]

          files[path.delete_prefix("#{@root}/")] = Digest::SHA256.file(path).hexdigest
        end
        files
      end

      def excluded?(name)
        return true if name.start_with?(".") && !@settings["include_hidden"].include?(name)

        @settings["exclude"].any? { |pattern| File.fnmatch?(pattern, name) } || name == "master.key" || name.end_with?(".key")
      end
    end
  end
end
