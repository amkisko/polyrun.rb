module Polyrun
  class Config
    module ToolDefaults
      STAGING = {"max_bytes" => 67_108_864, "max_files" => 10_000,
                 "exclude" => %w[vendor node_modules tmp log coverage pkg benchmarks],
                 "exclude_paths" => [], "include_hidden" => %w[.rspec .ruby-version]}.freeze
      COMMON = {"enabled" => false, "root" => nil, "workers" => 1, "timeout" => 300,
                "command" => [], "output" => nil, "max_output_bytes" => 1_048_576,
                "max_input_bytes" => 1_048_576, "max_artifact_bytes" => 67_108_864,
                "source_roots" => %w[lib app], "source_fallback" => true,
                "source_exclude" => %w[spec test features examples benchmarks vendor node_modules tmp log coverage pkg],
                "max_nodes" => 250_000, "max_source_files" => 100_000, "max_source_file_bytes" => 10_485_760,
                "max_source_bytes" => 67_108_864, "staging" => STAGING}.freeze
      SHARED = COMMON.except("enabled").freeze
      GRAPH = {"timeout" => 60, "state_dir" => ".polyrun/graph", "json" => false,
               "calls" => false, "callers" => false, "callees" => false, "control_plane" => false, "prove" => false,
               "max_operations" => 1000, "max_diff_bytes" => 524_288,
               "max_plan_bytes" => 1_048_576, "max_receipt_files" => 100_000}.freeze
      MUTATION = {"max_workers" => 32, "max_mutations" => 1000, "max_subjects" => 10_000,
                  "max_report_bytes" => 16_777_216, "max_copy_bytes" => 1_073_741_824,
                  "operators" => %w[literal operator body], "subjects" => [], "subjects_file" => nil,
                  "observed" => [], "plan" => nil, "shard" => 1, "total" => 1}.freeze
      OBSERVE = {"max_entries" => 10_000, "max_artifact_bytes" => 16_777_216}.freeze
      MEASURE = {"label" => "command", "ceilings" => {}}.freeze
      EXECUTION = %w[enabled root timeout command output max_output_bytes].freeze
      FEATURES = {"graph" => GRAPH, "mutation" => MUTATION, "observe" => OBSERVE, "measure" => MEASURE}.freeze

      module_function

      def for(feature)
        feature = feature.to_s
        common = case feature
        when "graph" then COMMON.except("workers")
        when "observe" then COMMON.slice(*EXECUTION, "max_artifact_bytes")
        when "measure" then COMMON.slice(*EXECUTION)
        else COMMON
        end
        Marshal.load(Marshal.dump(common.merge(FEATURES.fetch(feature))))
      end
    end
  end
end
