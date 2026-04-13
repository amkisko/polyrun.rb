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
        profile = nil
        output = nil
        dry_run = false
        force = false
        list = false

        op = OptionParser.new do |opts|
          opts.banner = "usage: polyrun init [--profile NAME] [--output PATH] [--dry-run] [--force]\n       polyrun init --list"
          opts.on("--profile NAME", INIT_PROFILES.keys.join(", ")) { |p| profile = p }
          opts.on("-o", "--output PATH", "destination file (default: polyrun.yml or POLYRUN.md for --profile doc)") { |p| output = p }
          opts.on("--dry-run", "print template to stdout; do not write") { dry_run = true }
          opts.on("--force", "overwrite existing output file") { force = true }
          opts.on("--list", "print available profiles") { list = true }
        end
        op.parse!(argv)

        if list
          Polyrun::Log.puts "polyrun init profiles:"
          INIT_PROFILES.each do |name, file|
            Polyrun::Log.puts "  #{name.ljust(12)} #{file}"
          end
          return 0
        end

        if profile.nil?
          Polyrun::Log.warn "polyrun init: specify --profile (#{INIT_PROFILES.keys.join(", ")}) or --list"
          return 2
        end

        filename = INIT_PROFILES[profile]
        unless filename
          Polyrun::Log.warn "polyrun init: unknown profile #{profile.inspect}"
          return 2
        end

        src = File.join(templates_dir, filename)
        unless File.file?(src)
          Polyrun::Log.warn "polyrun init: template missing: #{src}"
          return 1
        end

        body = File.read(src, encoding: Encoding::UTF_8)
        dest = output || default_init_output(profile)

        if dry_run
          Polyrun::Log.print body
          return 0
        end

        path = File.expand_path(dest)
        if File.file?(path) && !force
          Polyrun::Log.warn "polyrun init: #{path} exists (use --force to overwrite)"
          return 1
        end

        File.write(path, body)
        Polyrun::Log.warn "polyrun init: wrote #{path}"
        0
      end

      def default_init_output(profile)
        (profile == "doc") ? "POLYRUN.md" : "polyrun.yml"
      end
    end
  end
end
