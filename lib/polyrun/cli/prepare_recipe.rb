require "open3"

module Polyrun
  class CLI
    module PrepareRecipe
      private

      def prepare_recipe_default(manifest, recipe)
        Polyrun::Log.warn "polyrun prepare: default recipe (no side effects)" if @verbose
        [manifest, nil]
      end

      def prepare_recipe_assets(manifest, prep, dry, child_env)
        rails_root = File.expand_path(prep["rails_root"] || prep[:rails_root] || ".", Dir.pwd)
        manifest["rails_root"] = rails_root
        custom = prep["command"] || prep[:command]
        if dry
          manifest["actions"] = [
            custom ? custom.to_s.strip : "bin/rails assets:precompile"
          ]
          manifest["executed"] = false
          return [manifest, nil]
        end
        if custom && !custom.to_s.strip.empty?
          _out, err, st = Open3.capture3(*([child_env].compact + ["sh", "-c", custom.to_s]), chdir: rails_root)
          prepare_log_stderr(err)
          unless st.success?
            Polyrun::Log.warn "polyrun prepare: assets custom command failed (exit #{st.exitstatus})"
            return [manifest, 1]
          end
        else
          Polyrun::Prepare::Assets.precompile!(rails_root: rails_root, silent: !@verbose)
        end
        manifest["artifacts"] = [File.join(rails_root, "public", "assets").to_s]
        [manifest, nil]
      end

      def prepare_shell_command_lines(prep)
        command = prep["command"] || prep[:command]
        commands = prep["commands"] || prep[:commands]
        lines = []
        lines.concat(Array(commands).map { |c| c.to_s.strip }.reject(&:empty?)) if commands
        lines << command.to_s.strip if command && !command.to_s.strip.empty?
        lines
      end

      def prepare_recipe_shell(manifest, prep, dry, child_env)
        rails_root = File.expand_path(prep["rails_root"] || prep[:rails_root] || ".", Dir.pwd)
        manifest["rails_root"] = rails_root
        lines = prepare_shell_command_lines(prep)

        if lines.empty?
          Polyrun::Log.warn "polyrun prepare: shell recipe requires prepare.command and/or prepare.commands"
          return [manifest, 1]
        end
        manifest["actions"] = lines
        if dry
          manifest["executed"] = false
          return [manifest, nil]
        end
        lines.each_with_index do |line, i|
          _out, err, st = Open3.capture3(*([child_env].compact + ["sh", "-c", line]), chdir: rails_root)
          prepare_log_stderr(err)
          unless st.success?
            Polyrun::Log.warn "polyrun prepare: shell step #{i + 1} failed (exit #{st.exitstatus})"
            return [manifest, 1]
          end
        end
        [manifest, nil]
      end

      def prepare_log_stderr(err)
        Polyrun::Log.warn err unless err.to_s.empty?
      end
    end
  end
end
