require "json"

require_relative "constraints"
require_relative "hrw"
require_relative "min_heap"
require_relative "stable_shuffle"

module Polyrun
  module Partition
    # Assigns discrete items (e.g. spec paths) to shards (spec_queue.md).
    #
    # Strategies:
    # - +round_robin+ — sorted paths, assign by index mod +total_shards+.
    # - +random_round_robin+ — Fisher–Yates shuffle (optional +seed+), then same mod assignment.
    # - +cost_binpack+ (+cost+, +binpack+, +timing+) — LPT greedy binpack using per-path weights;
    #   optional {Constraints} for pins / serial globs before LPT on the rest.
    # - +hrw+ (+rendezvous+) — rendezvous hashing for minimal remapping when m changes; optional constraints.
    class Plan
      COST_STRATEGIES = %w[cost cost_binpack binpack timing].freeze
      HRW_STRATEGIES = %w[hrw rendezvous].freeze

      attr_reader :items, :total_shards, :strategy, :seed, :constraints

      def initialize(items:, total_shards:, strategy: "round_robin", seed: nil, costs: nil, constraints: nil, root: nil)
        @items = items.map(&:to_s).freeze
        @total_shards = Integer(total_shards)
        raise Polyrun::Error, "total_shards must be >= 1" if @total_shards < 1

        @strategy = strategy.to_s
        @seed = seed
        @root = root ? File.expand_path(root) : Dir.pwd
        @constraints = normalize_constraints(constraints)
        @costs = normalize_costs(costs)

        validate_constraints_strategy_combo!
        if cost_strategy? && (@costs.nil? || @costs.empty?)
          raise Polyrun::Error,
            "strategy #{@strategy} requires a timing map (path => seconds), e.g. merged polyrun_timing.json"
        end
      end

      def ordered_items
        @ordered_items ||= case strategy
        when "round_robin"
          items.sort
        when "random_round_robin"
          StableShuffle.call(items.sort, random_seed)
        when "cost", "cost_binpack", "binpack", "timing"
          items.sort
        when "hrw", "rendezvous"
          items.sort
        else
          raise Polyrun::Error, "unknown partition strategy: #{strategy}"
        end
      end

      def shard(shard_index)
        idx = Integer(shard_index)
        raise Polyrun::Error, "shard_index out of range" if idx < 0 || idx >= total_shards

        if cost_strategy?
          cost_shards[idx]
        elsif hrw_strategy?
          hrw_shards[idx]
        else
          mod_shards[idx]
        end
      end

      def shard_weight_totals
        if cost_strategy?
          cost_shards.map { |paths| paths.sum { |p| weight_for(p) } }
        elsif hrw_strategy?
          hrw_shards.map { |paths| paths.sum { |p| weight_for_optional(p) } }
        else
          []
        end
      end

      def manifest(shard_index)
        m = {
          "shard_index" => Integer(shard_index),
          "shard_total" => total_shards,
          "strategy" => strategy,
          "seed" => seed,
          "paths" => shard(shard_index)
        }
        secs = shard_weight_totals
        m["shard_seconds"] = secs if cost_strategy? || (hrw_strategy? && secs.any? { |x| x > 0 })
        m
      end

      def self.load_timing_costs(path)
        abs = File.expand_path(path.to_s, Dir.pwd)
        return {} unless File.file?(abs)

        data = JSON.parse(File.read(abs))
        return {} unless data.is_a?(Hash)

        out = {}
        data.each do |k, v|
          key = File.expand_path(k.to_s, Dir.pwd)
          out[key] = v.to_f
        end
        out
      end

      def self.cost_strategy?(name)
        COST_STRATEGIES.include?(name.to_s)
      end

      def self.hrw_strategy?(name)
        HRW_STRATEGIES.include?(name.to_s)
      end

      private

      def cost_strategy?
        self.class.cost_strategy?(strategy)
      end

      def hrw_strategy?
        self.class.hrw_strategy?(strategy)
      end

      def normalize_constraints(c)
        return nil if c.nil?

        c.is_a?(Constraints) ? c : Constraints.from_hash(c, root: @root)
      end

      def normalize_costs(costs)
        return nil if costs.nil?

        c = {}
        costs.each do |k, v|
          key = File.expand_path(k.to_s, @root)
          c[key] = v.to_f
        end
        c
      end

      def validate_constraints_strategy_combo!
        return unless @constraints&.any?
        return if cost_strategy? || hrw_strategy?

        raise Polyrun::Error,
          "partition constraints require strategy cost_binpack (with --timing) or hrw/rendezvous"
      end

      def default_weight
        return @default_weight if defined?(@default_weight)

        vals = @costs&.values || []
        @default_weight =
          if vals.empty?
            1.0
          else
            vals.sum / vals.size
          end
      end

      def weight_for(path)
        abs = File.expand_path(path.to_s, @root)
        return @costs[abs] if @costs&.key?(abs)

        default_weight
      end

      def weight_for_optional(path)
        abs = File.expand_path(path.to_s, @root)
        return @costs[abs] if @costs&.key?(abs)

        0.0
      end

      def cost_shards
        @cost_shards ||= build_lpt_buckets
      end

      def build_lpt_buckets
        PlanLptBuckets.new(self).build
      end
    end
  end
end

require_relative "plan_sharding"
require_relative "plan_lpt"
