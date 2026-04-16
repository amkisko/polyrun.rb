require "shellwords"

require_relative "log"
require_relative "hooks/dsl"
require_relative "hooks/worker_runner"
require_relative "hooks/worker_shell"

module Polyrun
  # Shell and Ruby DSL hooks around parallel orchestration, named like RSpec lifecycle callbacks:
  # +before_suite+ / +after_suite+ (+before(:suite)+ / +after(:suite)+),
  # +before_shard+ / +after_shard+ (parent process, per partition index),
  # +before_worker+ / +after_worker+ (inside each worker process, around the test command).
  #
  # Configure under +hooks:+ in +polyrun.yml+: shell strings, and/or +ruby:+ path to a Ruby DSL file.
  # Run manually: +polyrun hook run <phase>+ (see {CLI}).
  #
  # Orchestration respects +POLYRUN_HOOKS_DISABLE=1+ (+run_phase_if_enabled+); +polyrun hook run+ always runs {#run_phase}.
  class Hooks
    include WorkerShell

    PHASES = %i[
      before_suite after_suite
      before_shard after_shard
      before_worker after_worker
    ].freeze

    attr_reader :ruby_file

    def self.disabled?
      v = ENV["POLYRUN_HOOKS_DISABLE"].to_s.downcase
      %w[1 true yes].include?(v)
    end

    # When +POLYRUN_SHARD_TOTAL+ is greater than 1 (+ci-shard-run+ matrix), suite hooks are skipped by default; set
    # +POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB=1+ to run +before_suite+ / +after_suite+ on every matrix job (legacy).
    def self.suite_per_matrix_job?
      v = ENV["POLYRUN_HOOKS_SUITE_PER_MATRIX_JOB"].to_s.downcase
      %w[1 true yes].include?(v)
    end

    def self.from_config(cfg)
      raw = cfg.respond_to?(:hooks) ? cfg.hooks : {}
      new(raw.is_a?(Hash) ? raw : {})
    end

    # Maps CLI or YAML-style names (+before_suite+, +"before(:suite)"+) to a phase symbol or +nil+.
    def self.parse_phase(str)
      new({}).send(:canonical_key, str)
    end

    # @param raw [Hash] +hooks+ block from YAML
    def initialize(raw)
      @ruby_file = extract_ruby_file(raw)
      h = {}
      raw.each do |k, v|
        next if %w[ruby ruby_file].include?(k.to_s)

        ck = canonical_key(k)
        next if ck.nil?

        h[ck] = v
      end
      @raw = h.freeze
      @ruby_registry_loaded = false
      @ruby_registry = nil
    end

    def empty?
      no_shell = PHASES.all? { |p| commands_for(p).empty? }
      return false unless no_shell

      return true if @ruby_file.nil? || @ruby_file.to_s.strip.empty?
      return true unless File.file?(File.expand_path(@ruby_file, Dir.pwd))

      reg = ruby_registry
      reg.nil? || reg.empty?
    end

    def worker_hooks?
      return true if commands_for(:before_worker).any? || commands_for(:after_worker).any?

      !!ruby_registry&.worker_hooks?
    end

    # Merges +POLYRUN_HOOKS_RUBY_FILE+ when a DSL file is configured (for worker +ruby -e+).
    def merge_worker_ruby_env(env)
      return env unless @ruby_file
      abs = File.expand_path(@ruby_file, Dir.pwd)
      return env unless File.file?(abs)

      env.merge("POLYRUN_HOOKS_RUBY_FILE" => abs)
    end

    # @param phase [Symbol]
    # @return [Array<String>]
    def commands_for(phase)
      v = @raw[phase.to_sym]
      case v
      when nil then []
      when Array then v.map(&:to_s).map(&:strip).reject(&:empty?)
      else
        s = v.to_s.strip
        s.empty? ? [] : [s]
      end
    end

    # Runs Ruby DSL blocks (if any), then shell commands for +phase+.
    # @return [Integer] exit code (0 if no commands)
    def run_phase(phase, env)
      return 0 unless PHASES.include?(phase.to_sym)

      merged = stringify_env_for_hook(env).merge(
        "POLYRUN_HOOK_PHASE" => phase.to_s,
        "POLYRUN_HOOK" => "1"
      )

      reg = ruby_registry
      if reg&.any?(phase)
        begin
          reg.run(phase, merged)
        rescue => e
          Polyrun::Log.warn "polyrun hooks: #{phase} ruby hook failed: #{e.class}: #{e.message}"
          return 1
        end
      end

      commands_for(phase).each do |cmd|
        ok = system(merged, "sh", "-c", cmd)
        return $?.exitstatus unless ok
      end
      0
    end

    # Like {#run_phase}, but no-ops when {disabled?} (+POLYRUN_HOOKS_DISABLE=1+). Used by run-shards / ci-shard orchestration.
    def run_phase_if_enabled(phase, env)
      return 0 if self.class.disabled?

      run_phase(phase, env)
    end

    private

    def extract_ruby_file(raw)
      v = raw["ruby"] || raw[:ruby] || raw["ruby_file"] || raw[:ruby_file]
      return nil if v.nil?

      s = v.to_s.strip
      s.empty? ? nil : s
    end

    def ruby_registry
      return @ruby_registry if @ruby_registry_loaded

      @ruby_registry_loaded = true
      @ruby_registry = Dsl.load_registry(@ruby_file)
    end

    def stringify_env_for_hook(env)
      h = {}
      env.each { |k, v| h[k.to_s] = v }
      h
    end

    # Accept RSpec-style quoted keys from YAML, e.g. +"before(:suite)"+.
    def canonical_key(k)
      s = k.to_s.strip
      sym = if s.match?(/\Abefore\(\s*:suite\s*\)\z/i)
        :before_suite
      elsif s.match?(/\Aafter\(\s*:suite\s*\)\z/i)
        :after_suite
      elsif s.match?(/\Abefore\(\s*:all\s*\)\z/i)
        :before_shard
      elsif s.match?(/\Aafter\(\s*:all\s*\)\z/i)
        :after_shard
      elsif s.match?(/\Abefore\(\s*:each\s*\)\z/i)
        :before_worker
      elsif s.match?(/\Aafter\(\s*:each\s*\)\z/i)
        :after_worker
      else
        s.downcase.tr("-", "_").to_sym
      end
      PHASES.include?(sym) ? sym : nil
    end
  end
end
