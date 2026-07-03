require "json"
require "fileutils"

require_relative "coverage/example_diff"
require_relative "partition/timing_keys"
require_relative "spec_quality/config"
require_relative "spec_quality/profile"
require_relative "spec_quality/fragment"
require_relative "spec_quality/sql_counter"
require_relative "spec_quality/merge"
require_relative "spec_quality/plan_loader"
require_relative "spec_quality/report"
require_relative "spec_quality/rspec_hook"
require_relative "spec_quality/minitest_hook"

module Polyrun
  # Per-example spec quality: coverage line deltas, resource use, optional SQL counts.
  # Opt-in with +POLYRUN_SPEC_QUALITY=1+ or +Polyrun::SpecQuality.start!+.
  module SpecQuality
    class << self
      def start!(root: Dir.pwd, config_path: nil, output_path: nil, **overrides)
        return if Config.disabled?

        @config = Config.load(root: root, config_path: config_path, **overrides)
        @output_path = output_path || Fragment.default_fragment_path
        @pause_depth = 0
        @current = nil
        @rng = Random.new(Process.pid ^ Time.now.to_i)

        Fragment.truncate_fragment!(@output_path) unless fragment_append_mode?
        SqlCounter.install! if @config["sql_counter"]
        self
      end

      def started?
        instance_variable_defined?(:@config) && @config
      end

      def enabled?
        Config.enabled? && !Config.disabled?
      end

      def config
        @config
      end

      def output_path
        @output_path
      end

      def recording?
        started? && @current && @pause_depth.zero?
      end

      def start_example!(location:, wall_start: nil)
        return unless started?
        return if paused?
        return if Config.ignored_example?(location, @config["ignore_examples"])
        return unless sample_example?

        @current = {
          location: normalize_location(location),
          wall_start: wall_start || Process.clock_gettime(Process::CLOCK_MONOTONIC),
          coverage_before: Coverage::ExampleDiff.peek_blob,
          profile_before: Profile.snapshot,
          sql_count: 0,
          sql_fingerprints: Hash.new(0),
          factory_counts: {}
        }
        Polyrun::Data::FactoryCounts.reset_example! if defined?(Polyrun::Data::FactoryCounts)
        nil
      end

      def finish_example!(location: nil, pending: false)
        return unless started?
        cur = @current
        @current = nil
        return if cur.nil? || paused?
        return if pending

        loc = location || cur[:location]
        return if loc.nil? || loc.to_s.empty?

        after_cov = Coverage::ExampleDiff.peek_blob
        delta = Coverage::ExampleDiff.diff(cur[:coverage_before], after_cov)
        delta = Coverage::ExampleDiff.apply_track_under(
          delta,
          root: @config["root"],
          track_under: @config["track_under"],
          ignore_paths: @config["ignore_paths"]
        )

        profile_after = Profile.snapshot
        profile_delta = Profile.diff(cur[:profile_before], profile_after)
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - cur[:wall_start]
        profile_delta["wall"] = wall

        factory_counts =
          if defined?(Polyrun::Data::FactoryCounts)
            Polyrun::Data::FactoryCounts.example_counts
          else
            {}
          end

        row = build_row(cur, loc, delta, profile_delta, factory_counts)
        Fragment.append_row!(@output_path, row)
        row
      end

      def pause
        @pause_depth += 1
        if block_given?
          begin
            yield
          ensure
            resume
          end
        end
      end

      def resume
        @pause_depth -= 1 if @pause_depth.positive?
      end

      def paused?
        @pause_depth.positive?
      end

      def record_sql!(sql)
        return unless recording?

        @current[:sql_count] += 1
        fp = normalize_sql(sql)
        @current[:sql_fingerprints][fp] += 1
      end

      def spec_quality_requested_for_quick?(root = Dir.pwd)
        return false if Config.disabled?
        return true if %w[1 true yes].include?(ENV["POLYRUN_SPEC_QUALITY"]&.to_s&.downcase)
        return true if %w[1 true yes].include?(ENV["POLYRUN_SPEC_QUALITY_FRAGMENTS"]&.to_s&.downcase)

        path = File.join(File.expand_path(root), Config::DEFAULT_CONFIG_RELATIVE)
        return false unless File.file?(path)

        %w[1 true yes].include?(ENV["POLYRUN_QUICK_SPEC_QUALITY"]&.to_s&.downcase)
      end

      private

      def fragment_append_mode?
        truthy?(ENV["POLYRUN_SPEC_QUALITY_FRAGMENT_APPEND"])
      end

      def sample_example?
        rate = @config["sample"].to_f
        return true if rate >= 1.0
        return false if rate <= 0.0

        @rng.rand < rate
      end

      def normalize_location(location)
        s = location.to_s.strip
        return s if s.empty?

        root = @config["root"]
        if (m = s.match(/\A(.+):(\d+)\z/)) && m[2].match?(/\A\d+\z/)
          fp = Polyrun::Partition::TimingKeys.canonical_file_path(File.expand_path(m[1], root))
          return "#{fp}:#{m[2]}"
        end

        Polyrun::Partition::TimingKeys.canonical_file_path(File.expand_path(s, root))
      end

      def build_row(cur, location, delta, profile_delta, factory_counts)
        profile = Profile.slice_profile(profile_delta, @config["profile"])
        repeated_sql = cur[:sql_fingerprints].select { |_sql, n| n >= min_query_count }.transform_keys(&:to_s)

        {
          "example" => location.to_s,
          "unique_lines" => delta[:unique_lines],
          "line_churn" => delta[:line_churn],
          "max_line_churn" => delta[:max_line_churn],
          "lines" => delta[:lines],
          "profile" => profile,
          "sql_count" => cur[:sql_count],
          "repeated_sql" => repeated_sql,
          "factory_counts" => factory_counts.transform_keys(&:to_s),
          "polyrun_shard_index" => ENV["POLYRUN_SHARD_INDEX"],
          "polyrun_shard_total" => ENV["POLYRUN_SHARD_TOTAL"]
        }.compact
      end

      def min_query_count
        @config["min_query_count"].to_i
      end

      def normalize_sql(sql)
        sql.to_s.gsub(/\s+/, " ").strip[0, 500]
      end

      def truthy?(value)
        Config.send(:truthy?, value)
      end
    end
  end
end
