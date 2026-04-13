require "optparse"

module Polyrun
  class CLI
    module InitCommand
      INIT_PROFILES = {
        "gem" => "minimal_gem.polyrun.yml",
        "rails" => "rails_prepare.polyrun.yml",
        "ci-matrix" => "ci_matrix.polyrun.yml",
        "doc" => "POLYRUN.md"
      }.freeze

      private

      def templates_dir
        File.expand_path("../templates", __dir__)
      end

      def cmd_init(argv, _config_path)
        profile, output, dry_run, force, list = init_parse_options!(argv)
        return init_list_profiles if list
        return init_missing_profile if profile.nil?

        filename = INIT_PROFILES[profile]
        return init_unknown_profile(profile) unless filename

        src = File.join(templates_dir, filename)
        return init_missing_template(src) unless File.file?(src)

        body = File.read(src, encoding: Encoding::UTF_8)
        dest = output || default_init_output(profile)
        return init_dry_run_print(body) if dry_run

        path = File.expand_path(dest)
        return init_refuses_overwrite(path) if File.file?(path) && !force

        File.write(path, body)
        Polyrun::Log.warn "polyrun init: wrote #{path}"
        0
      end

      def init_parse_options!(argv)
        profile = nil
        output = nil
        dry_run = false
        force = false
        list = false

        OptionParser.new do |opts|
          opts.banner = "usage: polyrun init [--profile NAME] [--output PATH] [--dry-run] [--force]\n       polyrun init --list"
          opts.on("--profile NAME", INIT_PROFILES.keys.join(", ")) { |p| profile = p }
          opts.on("-o", "--output PATH", "destination file (default: polyrun.yml or POLYRUN.md for --profile doc)") { |p| output = p }
          opts.on("--dry-run", "print template to stdout; do not write") { dry_run = true }
          opts.on("--force", "overwrite existing output file") { force = true }
          opts.on("--list", "print available profiles") { list = true }
        end.parse!(argv)

        [profile, output, dry_run, force, list]
      end

      def init_list_profiles
        Polyrun::Log.puts "polyrun init profiles:"
        INIT_PROFILES.each do |name, file|
          Polyrun::Log.puts "  #{name.ljust(12)} #{file}"
        end
        0
      end

      def init_missing_profile
        Polyrun::Log.warn "polyrun init: specify --profile (#{INIT_PROFILES.keys.join(", ")}) or --list"
        2
      end

      def init_unknown_profile(profile)
        Polyrun::Log.warn "polyrun init: unknown profile #{profile.inspect}"
        2
      end

      def init_missing_template(src)
        Polyrun::Log.warn "polyrun init: template missing: #{src}"
        1
      end

      def init_dry_run_print(body)
        Polyrun::Log.print body
        0
      end

      def init_refuses_overwrite(path)
        Polyrun::Log.warn "polyrun init: #{path} exists (use --force to overwrite)"
        1
      end

      def default_init_output(profile)
        (profile == "doc") ? "POLYRUN.md" : "polyrun.yml"
      end
    end
  end
end
