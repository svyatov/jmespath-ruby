# frozen_string_literal: true

module JMESPath
  # Immutable parsed syntax that can search multiple input documents.
  class Expression
    # @return [String] an independent, frozen expression string
    attr_reader :source

    # @api private
    def initialize(source, root, max_depth: 128)
      @source = source.dup.freeze
      @root = root
      @max_depth = max_depth
      freeze
    end

    # Search input with this parsed expression.
    # @param data [Object] Ruby values, Pathname, IO, or StringIO
    # @param options [Hash] positional compatibility options
    # @param keywords [Hash] keyword evaluation options
    # @return [Object] the query result, including nil
    def search(data, options = {}, **keywords)
      config = Options.new(options, keywords, default_depth: @max_depth)
      evaluate(Input.load(data), config)
    end

    # @api private
    def evaluate(data, config)
      if @root.depth > config.max_depth
        raise Errors::SyntaxError.new("Expression exceeds nesting limit", expression: source)
      end

      Evaluator.new(functions: config.functions, disable_visit_errors: config.disable_visit_errors).evaluate(@root,
                                                                                                             data)
    end
  end
end
