require "fileutils"
require "json"
require "open3"

module Polyrun
  module Benchmark
    # Records benchmark output during performance specs and writes profile artifacts.
    # Set POLYRUN_BENCH=1 to echo lines to stdout. JSON sidecar enables report-benchmark exports.
    module Profile
      module_function

      def reset!
        lines_storage.clear
        metrics_storage.clear
        current_section_storage.replace(["default"])
      end

      def log(message = "")
        line = message.to_s
        lines_storage << line
        section = detect_section_title(line) || current_section_storage.first
        current_section_storage[0] = section if detect_section_title(line)
        $stdout.puts(line) if verbose? && !line.empty?
        line
      end

      def record_metric!(name:, value:, unit: "seconds", section: nil)
        section_name = section || current_section_storage.first
        metric = {
          "section" => section_name.to_s,
          "name" => name.to_s,
          "value" => value,
          "unit" => unit.to_s
        }
        metrics_storage << metric
        log(format_metric_line(metric))
        metric
      end

      def snapshot
        {
          "meta" => profile_meta,
          "lines" => lines_storage.dup,
          "metrics" => metrics_storage.dup
        }
      end

      def write!(repository_root: default_repository_root)
        data = snapshot
        return if data["lines"].empty? && data["metrics"].empty?

        log_path = output_path(repository_root: repository_root, extension: "log")
        json_path = output_path(repository_root: repository_root, extension: "json")
        FileUtils.mkdir_p(File.dirname(log_path))
        File.write(log_path, profile_header(data["meta"]) + data["lines"].join("\n") + "\n")
        File.write(json_path, JSON.pretty_generate(data))
        export_sidecars!(data, json_path)
        $stdout.puts("\nBenchmark profile written to #{log_path}") if verbose?
        log_path
      end

      def export_sidecars!(data, json_path)
        formats = export_formats
        return if formats.empty?

        require_relative "report"
        base = json_path.sub(/\.json\z/, "")
        formats.each do |format|
          path = "#{base}.#{export_extension(format)}"
          File.write(path, Report.render(data, format: format))
        end
      end

      def export_formats
        raw = ENV["POLYRUN_BENCH_FORMATS"]
        return [] if raw.nil? || raw.to_s.strip.empty?

        raw.split(",").map(&:strip).reject(&:empty?)
      end

      def export_extension(format)
        case format.to_s.downcase
        when "markdown", "md" then "md"
        when "text", "console", "txt" then "txt"
        else format.to_s.downcase
        end
      end

      def verbose?
        %w[1 true yes].include?(ENV["POLYRUN_BENCH"]&.to_s&.downcase)
      end

      def output_path(repository_root: default_repository_root, extension: "log", commit_sha: nil, working_tree_clean: nil, timestamp: nil)
        commit_identifier = commit_sha || self.commit_sha(repository_root: repository_root)
        clean_tree = working_tree_clean.nil? ? working_tree_clean?(repository_root: repository_root) : working_tree_clean
        filename = if clean_tree
          "profile_#{commit_identifier}.#{extension}"
        else
          recorded_at = timestamp || self.timestamp
          "profile_#{commit_identifier}_#{recorded_at}.#{extension}"
        end

        File.join(repository_root, "tmp", "benchmarks", filename)
      end

      def profile_meta(repository_root: default_repository_root)
        {
          "commit" => commit_sha(repository_root: repository_root),
          "recorded_at" => Time.now.utc.iso8601,
          "working_tree_clean" => working_tree_clean?(repository_root: repository_root),
          "ruby" => RUBY_VERSION,
          "polyrun_version" => Polyrun::VERSION
        }
      end

      def profile_header(meta)
        [
          "# Benchmark profile",
          "# commit: #{meta["commit"]}",
          "# recorded_at: #{meta["recorded_at"]}",
          "# working_tree_clean: #{meta["working_tree_clean"]}",
          "# ruby: #{meta["ruby"]}",
          ""
        ].join("\n")
      end

      def commit_sha(repository_root: default_repository_root)
        git_command("git rev-parse HEAD", repository_root: repository_root) || "unknown"
      end

      def working_tree_clean?(repository_root: default_repository_root)
        git_command("git status --porcelain", repository_root: repository_root).to_s.empty?
      end

      def timestamp
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      def git_command(command, repository_root:)
        stdout, status = Open3.capture2(command, chdir: repository_root)
        return nil unless status.success?

        stdout.strip
      rescue
        nil
      end

      def detect_section_title(line)
        return unless line.is_a?(String)
        return if line.strip.empty?
        return if line.start_with?("#")
        return unless line.end_with?(":")

        line.strip.delete_suffix(":")
      end

      def format_metric_line(metric)
        value = metric["value"]
        unit = metric["unit"]
        suffix = unit == "seconds" ? "s" : " #{unit}"
        format("  %s: %s%s", metric["name"], value, suffix)
      end

      def lines_storage
        @lines_storage ||= []
      end

      def metrics_storage
        @metrics_storage ||= []
      end

      def current_section_storage
        @current_section_storage ||= ["default"]
      end

      def default_repository_root
        Dir.pwd
      end
    end
  end
end
