require "json"
require "open3"
require "optparse"

module Polyrun
  class CLI
    module PrepareCommand
      private

      def cmd_prepare(argv, config_path)
        dry = false
        parser = OptionParser.new do |opts|
          opts.on("--dry-run", "Print steps only") { dry = true }
        end
        parser.parse!(argv)

        cfg = Polyrun::Config.load(path: config_path || ENV["POLYRUN_CONFIG"])
        prep = cfg.prepare
        recipe = prep["recipe"] || prep[:recipe] || "default"
        prep_env = (prep["env"] || prep[:env] || {}).transform_keys(&:to_s).transform_values(&:to_s)
        child_env = prep_env.empty? ? nil : ENV.to_h.merge(prep_env)
        manifest = {
          "recipe" => recipe,
          "dry_run" => dry,
          "artifacts" => [],
          "executed" => !dry
        }
        manifest["env"] = prep_env unless prep_env.empty?

        case recipe
        when "default", nil, ""
          Polyrun::Log.warn "polyrun prepare: default recipe (no side effects)" if @verbose
        when "assets"
          rails_root = File.expand_path(prep["rails_root"] || prep[:rails_root] || ".", Dir.pwd)
          manifest["rails_root"] = rails_root
          custom = prep["command"] || prep[:command]
          if dry
            manifest["actions"] = [
              custom ? custom.to_s.strip : "bin/rails assets:precompile"
            ]
            manifest["executed"] = false
          elsif custom && !custom.to_s.strip.empty?
            _out, err, st = Open3.capture3(*([child_env].compact + ["sh", "-c", custom.to_s]), chdir: rails_root)
            Polyrun::Log.warn err if !@verbose && !err.to_s.empty?
            Polyrun::Log.warn err if @verbose && !err.to_s.empty?
            unless st.success?
              Polyrun::Log.warn "polyrun prepare: assets custom command failed (exit #{st.exitstatus})"
              return 1
            end
            manifest["artifacts"] = [File.join(rails_root, "public", "assets").to_s]
          else
            Polyrun::Prepare::Assets.precompile!(rails_root: rails_root, silent: !@verbose)
            manifest["artifacts"] = [File.join(rails_root, "public", "assets").to_s]
          end
        when "shell"
          rails_root = File.expand_path(prep["rails_root"] || prep[:rails_root] || ".", Dir.pwd)
          manifest["rails_root"] = rails_root
          command = prep["command"] || prep[:command]
          commands = prep["commands"] || prep[:commands]
          lines = []
          lines.concat(Array(commands).map { |c| c.to_s.strip }.reject(&:empty?)) if commands
          lines << command.to_s.strip if command && !command.to_s.strip.empty?

          if lines.empty?
            Polyrun::Log.warn "polyrun prepare: shell recipe requires prepare.command and/or prepare.commands"
            return 1
          end
          manifest["actions"] = lines
          if dry
            manifest["executed"] = false
          else
            lines.each_with_index do |line, i|
              _out, err, st = Open3.capture3(*([child_env].compact + ["sh", "-c", line]), chdir: rails_root)
              Polyrun::Log.warn err if !@verbose && !err.to_s.empty?
              Polyrun::Log.warn err if @verbose && !err.to_s.empty?
              unless st.success?
                Polyrun::Log.warn "polyrun prepare: shell step #{i + 1} failed (exit #{st.exitstatus})"
                return 1
              end
            end
          end
        else
          Polyrun::Log.warn "unknown prepare recipe: #{recipe}"
          return 1
        end

        entries = (manifest["artifacts"] || []).map do |p|
          {"path" => p, "kind" => (File.directory?(p) ? "directory" : "file")}
        end
        artifact_path = Polyrun::Prepare::Artifacts.write!(root: Dir.pwd, recipe: recipe, entries: entries, dry_run: dry)
        manifest["artifact_manifest_path"] = artifact_path
        Polyrun::Log.puts JSON.generate(manifest)
        0
      end
    end
  end
end
