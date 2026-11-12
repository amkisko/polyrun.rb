module Polyrun
  module Quick
    # Optional host file +config/polyrun_quick.rb+ evaluated before Quick examples run.
    class Config
      PATH = "config/polyrun_quick.rb"

      attr_reader :before_suite_hooks, :after_suite_hooks, :load_paths

      def self.load!(root: Dir.pwd)
        cfg = new
        path = File.join(File.expand_path(root), PATH)
        return cfg unless File.file?(path)

        cfg.instance_eval(File.read(path), path)
        cfg
      end

      def initialize
        @before_suite_hooks = []
        @after_suite_hooks = []
        @load_paths = []
      end

      def before_suite(&block)
        @before_suite_hooks << block if block
      end

      def after_suite(&block)
        @after_suite_hooks << block if block
      end

      def add_load_path(path)
        @load_paths << path.to_s
      end

      def apply_load_paths!(root:)
        base = File.expand_path(root)
        @load_paths.each do |rel|
          abs = File.expand_path(rel, base)
          next unless File.directory?(abs)
          next if $LOAD_PATH.include?(abs)

          $LOAD_PATH.unshift(abs)
        end
      end

      def run_before_suite!
        @before_suite_hooks.each(&:call)
      end

      def run_after_suite!(status)
        @after_suite_hooks.each { |h| h.call(status) }
      end
    end
  end
end
