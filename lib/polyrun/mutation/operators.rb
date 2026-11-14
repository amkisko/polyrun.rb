module Polyrun
  module Mutation
    module Operators
      class Literal
        def call(node)
          replacements = case node
          when Prism::TrueNode then ["false"]
          when Prism::FalseNode then ["true"]
          when Prism::NilNode then ["true"]
          when Prism::IntegerNode then ["0", "1", (node.value + 1).to_s]
          when Prism::FloatNode then ["0.0", "1.0"]
          when Prism::StringNode, Prism::InterpolatedStringNode then ['""']
          when Prism::ArrayNode then ["[]"]
          when Prism::HashNode then ["{}"]
          else []
          end
          replacements.map { |value| [node.location, value, "literal"] }
        end
      end

      class Operator
        REPLACEMENTS = {"==" => "!=", "!=" => "==", ">" => "<=", ">=" => "<", "<" => ">=", "<=" => ">",
                        "+" => "-", "-" => "+", "*" => "/", "/" => "*", "&" => "|", "|" => "&"}.freeze

        def call(node)
          return [] unless node.is_a?(Prism::CallNode) && node.message_loc

          replacement = REPLACEMENTS[node.name.to_s]
          replacement ? [[node.message_loc, replacement, "operator"]] : []
        end
      end

      class Body
        def call(node)
          return [] unless node.is_a?(Prism::DefNode)

          return %w[false true 0].map { |value| [node.end_keyword_loc.copy(length: 0), ";#{value};", "body"] } unless node.body

          %w[nil false true 0].map { |value| [node.body.location, value, "body"] }
        end
      end

      REGISTRY = {"literal" => Literal.new, "operator" => Operator.new, "body" => Body.new}.freeze
      STANDARD = REGISTRY.values.freeze

      def self.select(names)
        names.map { |name| REGISTRY.fetch(name) }
      end
    end
  end
end
