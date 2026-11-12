module Polyrun
  module Quick
    # One +describe+ / +with+ block (possibly nested). Holds examples and hooks.
    class ExampleGroup
      attr_reader :name, :parent, :children, :examples, :before_hooks, :after_hooks, :around_hooks,
        :lets, :let_bang_order, :described_target

      def initialize(name, parent: nil, described_target: nil)
        @name = name_label(name)
        @described_target = described_target.nil? ? infer_described_target(name) : described_target
        @parent = parent
        @children = []
        @examples = []
        @before_hooks = []
        @after_hooks = []
        @around_hooks = []
        @lets = {}
        @let_bang_order = []
        maybe_default_subject!
      end

      def full_name
        return @name if parent.nil?

        "#{parent.full_name} #{@name}".strip
      end

      def describe(name, &block)
        child = ExampleGroup.new(name, parent: self)
        @children << child
        child.instance_eval(&block) if block
        child
      end

      alias_method :with, :describe

      def it(description, &block)
        @examples << [description.to_s, block]
      end

      alias_method :test, :it

      def before(&block)
        @before_hooks << block
      end

      def after(&block)
        @after_hooks << block
      end

      def around(&block)
        @around_hooks << block
      end

      def let(name, &block)
        @lets[name.to_sym] = block
      end

      def let!(name, &block)
        sym = name.to_sym
        @lets[sym] = block
        @let_bang_order << sym
      end

      def subject(&block)
        if block
          let(:subject, &block)
        else
          # Used from examples via ExampleRunner method; group-level call without block is invalid.
          raise ArgumentError, "subject requires a block at describe time"
        end
      end

      def each_example_with_ancestors(ancestors = [], &visitor)
        chain = ancestors + [self]
        @examples.each do |desc, block|
          visitor.call(chain, desc, block)
        end
        @children.each do |child|
          child.each_example_with_ancestors(chain, &visitor)
        end
      end

      private

      def name_label(name)
        return name.to_s unless name.is_a?(Module)

        name.name || name.to_s
      end

      def infer_described_target(name)
        name.is_a?(Module) ? name : nil
      end

      def maybe_default_subject!
        return unless @described_target
        return if @lets.key?(:subject)

        target = @described_target
        @lets[:subject] = -> {
          if target.respond_to?(:new)
            target.new
          else
            target
          end
        }
      end
    end
  end
end
