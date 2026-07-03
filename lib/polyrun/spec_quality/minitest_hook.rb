module Polyrun
  module SpecQuality
    # Minitest hook: per-test spec quality (requires minitest loaded).
    module MinitestHook
      module SpecQualityTestHook
        def setup
          Polyrun::SpecQuality.start_example!(location: polyrun_minitest_location)
          super
        end

        def teardown
          super
          Polyrun::SpecQuality.finish_example!(location: polyrun_minitest_location)
        end

        private

        def polyrun_minitest_location
          file, line = method(name).source_location
          (file && line) ? "#{file}:#{line}" : nil
        rescue NameError
          nil
        end
      end

      module_function

      def install!(only_if: nil, root: nil, output_path: nil)
        pred = only_if || -> { Polyrun::SpecQuality.enabled? }
        return unless pred.call

        unless defined?(::Minitest::Test)
          Polyrun::Log.warn "polyrun minitest: install_spec_quality! skipped (load minitest first)"
          return
        end

        Polyrun::SpecQuality::RspecHook.ensure_started!(root: root, output_path: output_path)
        ::Minitest::Test.send(:prepend, SpecQualityTestHook)
      end
    end
  end
end
