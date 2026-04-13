require "json"
require "open3"
require "optparse"

require_relative "prepare_recipe"

module Polyrun
  class CLI
    module PrepareCommand
      include PrepareRecipe

      private

      def cmd_prepare(argv, config_path)
        dry = false
        OptionParser.new do |opts|
          opts.on("--dry-run", "Print steps only") { dry = true }
        end.parse!(argv)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        prep = cfg.prepare
        recipe = prep["recipe"] || prep[:recipe] || "default"
        prep_env = (prep["env"] || prep[:env] || {}).transform_keys(&:to_s).transform_values(&:to_s)
        child_env = prep_env.empty? ? nil : ENV.to_h.merge(prep_env)
        manifest = prepare_build_manifest(recipe, dry, prep_env)

        exit_code = prepare_dispatch_recipe(manifest, prep, recipe, dry, child_env)
        return exit_code unless exit_code.nil?

        prepare_write_artifact_manifest!(manifest, recipe, dry)
      end

      def prepare_write_artifact_manifest!(manifest, recipe, dry)
        entries = (manifest["artifacts"] || []).map do |p|
          {"path" => p, "kind" => (File.directory?(p) ? "directory" : "file")}
        end
        manifest["artifact_manifest_path"] = Polyrun::Prepare::Artifacts.write!(root: Dir.pwd, recipe: recipe, entries: entries, dry_run: dry)
        Polyrun::Log.puts JSON.generate(manifest)
        0
      end

      def prepare_build_manifest(recipe, dry, prep_env)
        manifest = {
          "recipe" => recipe,
          "dry_run" => dry,
          "artifacts" => [],
          "executed" => !dry
        }
        manifest["env"] = prep_env unless prep_env.empty?
        manifest
      end

      def prepare_dispatch_recipe(manifest, prep, recipe, dry, child_env)
        case recipe
        when "default", nil, ""
          prepare_recipe_default(manifest, recipe)
          nil
        when "assets"
          m, err = prepare_recipe_assets(manifest, prep, dry, child_env)
          err
        when "shell"
          m, err = prepare_recipe_shell(manifest, prep, dry, child_env)
          err
        else
          Polyrun::Log.warn "unknown prepare recipe: #{recipe}"
          1
        end
      end
    end
  end
end
