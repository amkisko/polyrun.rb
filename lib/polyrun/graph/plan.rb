require "json"
require "digest"
require "find"
require_relative "error"
require_relative "workspace"
require "prism"
require_relative "transaction"

module Polyrun
  module Graph
    class Plan
      attr_reader :tree, :directory

      def initialize(root, id, settings: {})
        raise Error.new("INVALID_PLAN", "invalid plan id") unless id.is_a?(String) && id.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z/)

        @settings = Config::Tools.runtime("graph", settings)
        @root = File.realpath(root)
        @directory = safe_path(@root, "#{@settings["state_dir"]}/plans/#{id}")
        @tree = safe_path(@directory, "tree")
      end

      def metadata
        read_json(safe_path(@directory, "meta.json"))
      end

      def verify!
        receipt = read_json(safe_path(@directory, "polyrun-check.json"))
        raise Error.new("CHECK_FAILED", "plan changed since check") unless receipt == fingerprint

        verify_originals!
        true
      end

      def record_check!
        check = read_json(safe_path(@directory, "check.json"))
        raise Error.new("CHECK_FAILED", "graph check did not succeed") unless check["status"] == "ok"

        verify_originals!
        receipt = JSON.generate(fingerprint)
        raise Error.new("RESOURCE_LIMIT", "plan receipt is too large") if receipt.bytesize > @settings["max_plan_bytes"]

        File.write(safe_path(@directory, "polyrun-check.json"), receipt)
      end

      def invalidate!
        %w[check.json polyrun-check.json].each do |name|
          path = safe_path(@directory, name)
          File.unlink(path) if File.exist?(path)
        end
      end

      def verify_originals!
        hashes = metadata.fetch("pre_hashes")
        raise Error.new("INVALID_PLAN", "invalid original file hashes") unless hashes.is_a?(Hash) && !hashes.empty?

        hashes.each do |relative, expected|
          path = safe_path(@root, relative)
          staged = safe_path(@tree, relative)
          raise Error.new("INVALID_PLAN", "staged file missing: #{relative}") unless File.file?(staged)
          unless File.file?(path) && Digest::SHA256.file(path).hexdigest == expected
            raise Error.new("STALE_SNAPSHOT", "file changed before apply: #{relative}")
          end
        end
        raise Error.new("STALE_SNAPSHOT", "source file inventory changed") unless Workspace.new(@root, settings: @settings).files == hashes.keys.sort
      end

      def check!
        verify_originals!
        metadata.fetch("pre_hashes").each_key do |relative|
          path = safe_path(@tree, relative)
          raise Error.new("PARSE_FAILED", "invalid staged Ruby: #{relative}") if Prism.parse_file(path).failure?
          expected = metadata.fetch("staged_hashes").fetch(relative)
          raise Error.new("CHECK_FAILED", "staged operation changed: #{relative}") unless Digest::SHA256.file(path).hexdigest == expected
        end
        result = {"ok" => true, "status" => "ok", "provenance" => "syntax"}
        File.write(safe_path(@directory, "check.json"), JSON.generate(result))
        result
      end

      def apply!
        transaction = Transaction.new(@root, @directory, settings: @settings)
        transaction.recover!
        verify!
        replacements = metadata.fetch("pre_hashes").keys.filter_map do |relative|
          original = safe_path(@root, relative)
          staged = safe_path(@tree, relative)
          [relative, File.binread(original), File.binread(staged)] if Digest::SHA256.file(original).hexdigest != Digest::SHA256.file(staged).hexdigest
        end
        transaction.commit(replacements)
      end

      private

      def fingerprint
        files = {}
        Find.find(@tree) do |path|
          raise Error.new("INVALID_PLAN", "symbolic link in plan tree") if File.symlink?(path)
          next if File.directory?(path)
          raise Error.new("INVALID_PLAN", "nonregular file in plan tree") unless File.file?(path)
          raise Error.new("INVALID_PLAN", "too many plan files") if files.length >= @settings["max_receipt_files"]

          files[path.delete_prefix("#{@tree}/")] = Digest::SHA256.file(path).hexdigest
        end
        {"metadata" => Digest::SHA256.file(safe_path(@directory, "meta.json")).hexdigest, "files" => files}
      end

      def safe_path(base, relative)
        parts = relative.is_a?(String) ? relative.split("/", -1) : []
        if parts.empty? || parts.any? { |part| part.empty? || part == "." || part == ".." } || relative.include?("\0")
          raise Error.new("INVALID_PLAN", "invalid plan path")
        end
        parts.reduce(base) do |parent, part|
          path = File.join(parent, part)
          raise Error.new("INVALID_PLAN", "symbolic link in plan path") if File.symlink?(path)

          path
        end
      end

      def read_json(path)
        raise Error.new("CHECK_FAILED", "check or plan metadata missing") unless File.file?(path)
        raise Error.new("INVALID_PLAN", "plan metadata too large") if File.size(path) > @settings["max_plan_bytes"]

        value = JSON.parse(File.binread(path))
        raise Error.new("INVALID_PLAN", "plan metadata must be an object") unless value.is_a?(Hash)

        value
      rescue JSON::ParserError => e
        raise Error.new("INVALID_PLAN", e.message)
      end
    end
  end
end
