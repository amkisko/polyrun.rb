module Polyrun
  module SpecQuality
    # RSpec hooks for per-example spec quality recording.
    module RspecHook
      module_function

      def install!(only_if: nil, root: nil, output_path: nil)
        pred = only_if || -> { Polyrun::SpecQuality.enabled? }
        return unless pred.call

        require "rspec/core"
        ensure_started!(root: root, output_path: output_path)

        ::RSpec.configure do |config|
          config.before(:each) do |example|
            next if example.pending?

            Polyrun::SpecQuality.start_example!(
              location: example.metadata[:location] || example.location
            )
          end

          config.after(:each) do |example|
            Polyrun::SpecQuality.finish_example!(
              location: example.metadata[:location] || example.location,
              pending: example.pending?
            )
          end
        end
      end

      def ensure_started!(root: nil, output_path: nil)
        return if Polyrun::SpecQuality.started?

        Polyrun::SpecQuality.start!(
          root: root || infer_root,
          output_path: output_path
        )
      end

      def infer_root
        if defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root
          return ::Rails.root.to_s
        end

        caller_locations.each do |loc|
          inferred = Polyrun::Coverage::Rails.infer_root_from_path(loc.path)
          return inferred if inferred
        end

        Dir.pwd
      end
    end
  end
end
