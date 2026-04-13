require "digest/sha2"
require "json"

module Polyrun
  module Prepare
    # Writes +polyrun-artifacts.json+ (spec2 §3) for cache keys and CI upload lists.
    module Artifacts
      VERSION = 1

      module_function

      # +entries+ is array of hashes: { "path" => ..., "kind" => "file"|"directory", optional "digest", "size" }
      def write!(root:, recipe:, entries:, dry_run: false)
        list = entries.map { |e| normalize_entry(e) }
        doc = {
          "version" => VERSION,
          "recipe" => recipe,
          "dry_run" => dry_run,
          "generated_at" => Time.now.utc.iso8601,
          "artifacts" => list
        }
        path = File.join(root, "polyrun-artifacts.json")
        File.write(path, JSON.pretty_generate(doc))
        path
      end

      def normalize_entry(e)
        h = e.transform_keys(&:to_s)
        p = h["path"].to_s
        kind = h["kind"] || (File.directory?(p) ? "directory" : "file")
        out = {"path" => p, "kind" => kind}
        if File.exist?(p)
          out["size"] = File.size(p) if File.file?(p)
          out["digest"] = h["digest"] || (File.file?(p) ? "sha256:#{Digest::SHA256.file(p).hexdigest}" : nil)
        end
        out.compact
      end
    end
  end
end
