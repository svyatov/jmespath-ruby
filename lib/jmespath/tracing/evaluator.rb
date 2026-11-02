# frozen_string_literal: true

module JMESPath
  module Tracing
    # @api private
    class Evaluator < JMESPath::Evaluator
      def initialize(config:, collector:, root:, planned:, native_functions:)
        @collector = collector
        @native_functions = planned ? native_functions : nil
        @compiled_functions = {} # : Hash[AST::Node, bool]
                              .compare_by_identity
        index_plan(root) if planned
        @compiled_functions.freeze
        super(functions: config.functions, disable_visit_errors: config.disable_visit_errors)
      end

      def evaluate(node, data)
        return super unless node.kind == :field

        result, reason = FieldLookup.call(data, node.value.to_s)
        @collector.emit("field_null", node, name: node.value.to_s, reason: reason) if reason
        result
      end

      private

      def index_plan(node)
        return unless Plan::BUILDERS.key?(node.kind)

        @compiled_functions[node] = true if node.kind == :function
        node.children.each { |child| index_plan(child) }
      end

      def function(node, data)
        return super unless @compiled_functions.key?(node) && !@disable_visit_errors

        arguments = node.children.map { |child| evaluate(child, data) }
        return native_string(node, arguments.fetch(0)) if @native_functions&.include?(node)

        @functions.call_with_context(node.value.to_s, arguments, source_range: node.start...node.finish)
      end

      def native_string(node, value)
        if value.is_a?(String)
          node.value == "length" ? value.length : value.reverse
        else
          Functions.default.call_with_context(node.value.to_s, [value], source_range: node.start...node.finish)
        end
      end

      def reference(node, _data)
        ExpressionReference.new do |value|
          @collector.reference(node) { evaluate(node.children.fetch(0), value) }
        end
      end

      def project(node, values)
        return nil unless values

        index = -1
        child = node.children.fetch(1)
        result = values.map do |value|
          index += 1
          project_item(node, child, value, index)
        end
        result.compact!
        result
      end

      def project_item(node, child, value, index)
        @collector.within(node, index) do
          result = evaluate(child, value)
          @collector.emit("projection_omission", node) if nil.equal?(result)
          result
        end
      end

      def filter_projection(node, data)
        values = DataAccess.array(evaluate(node.children.fetch(0), data))
        indexes = [] # : Array[Integer]
        index = -1
        selected = values&.reject do |value|
          index += 1
          rejected = filter_rejected?(node, value, index)
          indexes << index unless rejected
          rejected
        end
        return nil unless selected

        project_selected(node, selected, indexes)
      end

      def filter_rejected?(node, value, index)
        @collector.within(node, index) do
          rejected = Types.falsey?(evaluate(node.children.fetch(2), value))
          @collector.emit("filter_exclusion", node) if rejected
          rejected
        end
      end

      def project_selected(node, selected, indexes)
        position = -1
        child = node.children.fetch(1)
        selected.map! do |value|
          position += 1
          project_item(node, child, value, indexes.fetch(position))
        end
        selected.compact!
        selected
      end
    end
  end
end
