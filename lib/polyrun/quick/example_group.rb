module Polyrun
  module Quick
    # One +describe+ block (possibly nested). Holds +it+ / +test+ examples and hooks.
    class ExampleGroup
      attr_reader :name, :parent, :children, :examples, :before_hooks, :after_hooks, :lets, :let_bang_order

      def initialize(name, parent: nil)
        @name = name.to_s
        @parent = parent
        @children = []
        @examples = []
        @before_hooks = []
        @after_hooks = []
        @lets = {}
        @let_bang_order = []
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

      def let(name, &block)
        @lets[name.to_sym] = block
      end

      def let!(name, &block)
        sym = name.to_sym
        @lets[sym] = block
        @let_bang_order << sym
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
    end
  end
end
