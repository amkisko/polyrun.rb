require "securerandom"
require "yaml"
require_relative "index"
require_relative "plan"
require_relative "../quality/sandbox"

module Polyrun
  module Graph
    class Planner
      def initialize(root, settings: {})
        @workspace = Workspace.new(root, settings: settings)
      end

      def call(change_path)
        change = load_change(change_path)
        index = fresh_index(change)
        operations = change["operations"]
        raise Error.new("INVALID_PLAN", "operations must be a nonempty array") unless operations.is_a?(Array) && (1..@workspace.settings["max_operations"]).cover?(operations.length)

        replacements = prepare(operations, index)
        id = "plan-#{SecureRandom.hex(12)}"
        plan = Plan.new(@workspace.root, id, settings: @workspace.settings)
        stage_plan(plan, replacements)
        save_plan(plan, id, index, operations)
        hashes = index.fetch("files")
        {"ok" => true, "plan_id" => id, "diff" => diff(plan, hashes)}
      rescue JSON::ParserError, Psych::Exception, KeyError, TypeError => error
        raise Error.new("INVALID_PLAN", error.message)
      end

      private

      def stage_plan(plan, replacements)
        Quality::Sandbox.new(@workspace.root, settings: @workspace.settings["staging"].merge("exclude_paths" => @workspace.settings["staging"]["exclude_paths"] + [@workspace.state])).copy_to(plan.tree)
        write_edits(plan, replacements)
      end

      def save_plan(plan, id, index, operations)
        hashes = index.fetch("files")
        staged = hashes.keys.to_h { |relative| [relative, Digest::SHA256.file(@workspace.path(relative, base: plan.tree)).hexdigest] }
        @workspace.write_json("#{@workspace.state}/plans/#{id}/meta.json", {"id" => id, "snapshot" => index["snapshot"],
          "pre_hashes" => hashes, "staged_hashes" => staged, "operations" => operations}, limit: @workspace.settings["max_plan_bytes"])
      end

      def load_change(change_path)
        file = File.expand_path(change_path, @workspace.root)
        raise Error.new("RESOURCE_LIMIT", "change description is too large") if File.size(file) > @workspace.settings["max_input_bytes"]

        raw = File.read(file)
        raw.lstrip.start_with?("{") ? JSON.parse(raw) : YAML.safe_load(raw)
      end

      def fresh_index(change)
        index = Index.new(@workspace.root, settings: @workspace.settings).load
        hashes = @workspace.hashes
        unless change.is_a?(Hash) && change["snapshot"] == index["snapshot"] && hashes == index["files"]
          raise Error.new("STALE_SNAPSHOT", "index the current source before planning changes")
        end
        index
      end

      def write_edits(plan, replacements)
        replacements.group_by { |operation| operation.fetch("path") }.each do |relative, edits|
          path = @workspace.path(relative, base: plan.tree)
          source = File.binread(path)
          edits.sort_by { |edit| -edit.fetch("byte_start") }.each do |edit|
            source[edit["byte_start"]...edit["byte_end"]] = edit["replacement"]
          end
          raise Error.new("PARSE_FAILED", "replacement is not valid Ruby") if Prism.parse(source).failure?

          File.binwrite(path, source)
        end
      end

      def prepare(operations, index)
        nodes = index["calls"].to_h { |node| [node["id"], node] }
        seen = {}
        operations.map do |operation|
          raise Error.new("INVALID_PLAN", "unsupported graph operation") unless operation.is_a?(Hash) && operation["op"] == "replace_call_name"

          node = nodes[operation["node"]]
          raise Error.new("UNKNOWN_TARGET", "call site missing") unless node
          raise Error.new("INVALID_PLAN", "duplicate call-site operation") if seen[node["id"]]

          seen[node["id"]] = true
          validate_edit!(operation, node)
          node.merge("replacement" => operation["replacement"].b)
        end
      end

      def validate_edit!(operation, node)
        raise Error.new("EXPECT_MISMATCH", "call-site fingerprint changed") unless operation["expect"] == node.slice("name", "fingerprint")

        replacement = operation["replacement"]
        unless replacement.is_a?(String) && replacement.match?(/\A[[:alpha:]_][[:alnum:]_]*[!?=]?\z/)
          raise Error.new("INVALID_PLAN", "replacement must be a method name")
        end
        original = File.binread(@workspace.path(node["path"])).byteslice(node["byte_start"]...node["byte_end"])
        raise Error.new("EXPECT_MISMATCH", "call-site bytes changed or unsupported target") unless original == node["name"].b
      end

      def diff(plan, hashes)
        text = hashes.keys.filter_map do |relative|
          before = File.binread(@workspace.path(relative))
          after = File.binread(@workspace.path(relative, base: plan.tree))
          next if before == after

          "--- a/#{relative}\n+++ b/#{relative}\n@@ -1,#{before.lines.size} +1,#{after.lines.size} @@\n" +
            before.lines.map { |line| "-#{line.chomp}\n" }.join + after.lines.map { |line| "+#{line.chomp}\n" }.join
        end.join
        raise Error.new("RESOURCE_LIMIT", "plan diff is too large") if text.bytesize > @workspace.settings["max_diff_bytes"]

        text
      end
    end
  end
end
