# frozen_string_literal: true

module JMESPath
  # @api private
  module Plan
    BUILDERS = {
      field: :field, current: :current, group: :group,
      subexpression: :sequence, pipe: :sequence, index: :index,
      multi_select_list: :list, projection: :projection,
      value_projection: :value_projection, slice: :slice, function: :function,
      expression_reference: :reference
    }.freeze

    def self.build(node, options = Options::DEFAULT)
      builder = Builder.new(options)
      operation = builder.build(node)
      native_functions = builder.native_functions&.freeze
      builder.freeze
      yield native_functions
      operation
    end

    # @api private
    class Builder
      attr_reader :native_functions

      def initialize(options)
        @native_functions = nil
        @functions = options.functions
        @disable_visit_errors = options.disable_visit_errors
        @evaluator = if @functions.equal?(Functions.default) && !@disable_visit_errors
                       Expression::DEFAULT_EVALUATOR
                     else
                       Evaluator.new(functions: @functions, disable_visit_errors: @disable_visit_errors)
                     end
      end

      def build(node)
        builder = BUILDERS[node.kind]
        (builder ? send(builder, node) : fallback(node)).freeze
      end

      private

      def field(node)
        DataAccess::FieldReader.new(node.value.to_s)
      end

      def current(_node)
        ->(data) { data }
      end

      def group(node)
        build(node.children.fetch(0))
      end

      def sequence(node)
        children = node.children.map { |child| build(child) }.freeze
        lambda do |data|
          children.each { |child| data = child.call(data) }
          data
        end
      end

      def index(node)
        child = build(node.children.fetch(0))
        position = Integer(node.value) # : Integer
        lambda do |data|
          values = DataAccess.array(child.call(data))
          values[position] if values && position.between?(-values.length, values.length - 1)
        end
      end

      def list(node)
        children = node.children.map { |child| build(child) }.freeze
        ->(data) { children.map { |child| child.call(data) } unless data.nil? }
      end

      def projection(node)
        child = build(node.children.fetch(0))
        project = projector(node.children.fetch(1))
        ->(data) { project.call(DataAccess.array(child.call(data))) }
      end

      def value_projection(node)
        child = build(node.children.fetch(0))
        project = projector(node.children.fetch(1))
        ->(data) { project.call(DataAccess.object(child.call(data))&.values) }
      end

      def projector(node)
        child = build(node)
        lambda do |values|
          if values
            result = values.map { |value| child.call(value) }
            result.compact!
            result
          end
        end
      end

      def slice(node)
        child = build(node.children.fetch(0))
        start, stop, step = Array(node.value).map { |part| part.nil? ? nil : Integer(part) }
        slice = Slice.new(start: start, stop: stop, step: step).freeze
        lambda do |data|
          values = DataAccess.array(child.call(data))
          slice.apply(values) if values
        end
      end

      def function(node)
        name = node.value.to_s
        source_range = (node.start...node.finish)
        unless !@disable_visit_errors && %w[length reverse].include?(name) && node.children.length == 1 &&
               native_function?(name)
          return function_call(name, node.children, source_range)
        end

        build_native_string(node, name, source_range)
      end

      def build_native_string(node, name, source_range)
        # @type var native_functions: Array[AST::Node]
        native_functions = @native_functions || []
        native_functions << node
        @native_functions = native_functions
        string_function(name, build(node.children.fetch(0)), source_range)
      end

      def native_function?(name)
        @functions.instance_of?(Functions) && @functions.definition(name).equal?(Functions.default.definition(name))
      end

      def string_function(name, child, source_range)
        lambda do |data|
          value = child.call(data)
          if value.is_a?(String)
            name == "length" ? value.length : value.reverse
          else
            Functions.default.call_with_context(name, [value], source_range: source_range)
          end
        end
      end

      def fallback(node)
        evaluator = @evaluator
        ->(data) { evaluator.evaluate(node, data) }
      end

      def function_call(name, nodes, source_range)
        arguments = nodes.map { |node| build(node) }.freeze
        functions = @functions
        if @disable_visit_errors
          lambda do |data|
            functions.call_with_context(name, arguments.map { |argument| argument.call(data) },
                                        source_range: source_range, disable_visit_errors: true)
          end
        else
          lambda do |data|
            functions.call_with_context(name, arguments.map do |argument|
              argument.call(data)
            end, source_range: source_range)
          end
        end
      end

      def reference(node)
        operation = build(node.children.fetch(0))
        ->(_data) { ExpressionReference.new { |value| operation.call(value) } }
      end
    end
  end
end
