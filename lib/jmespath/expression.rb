# frozen_string_literal: true

module JMESPath
  # Immutable parsed syntax that can search multiple input documents.
  class Expression
    DEFAULT_EVALUATOR = Evaluator.new(functions: Functions.default)
    # @return [String] an independent, frozen expression string
    attr_reader :source

    # @api private
    def initialize(source, root, max_depth: 128, options: Options::DEFAULT)
      @source = source.dup.freeze
      @root = root
      @options = options
      @plan = Plan.build(root, options)
      @max_depth = max_depth
      freeze
    end

    # Search input with this parsed expression.
    # @param data [Object] Ruby values, Pathname, IO, or StringIO
    # @param options [Hash] positional compatibility options
    # @param keywords [Hash] keyword evaluation options
    # @return [Object] the query result, including nil
    def search(data, options = Options::EMPTY, **keywords)
      if options.equal?(Options::EMPTY) && keywords.empty?
        return @plan.call(data.is_a?(Hash) ? data : Input.load(data))
      end

      config = Options.new(options, keywords, default_depth: @max_depth, defaults: @options)
      evaluate(Input.load(data), config)
    end

    # Search input using the same options and behavior as {#search}.
    # @return [Object] the query result, including nil
    alias call search

    # @api private
    def configured(options)
      return self if options.functions.equal?(Functions.default) && !options.disable_visit_errors

      self.class.new(source, @root, max_depth: @max_depth, options: options)
    end

    # @api private
    def evaluate(data, config)
      if @root.depth > config.max_depth
        raise Errors::SyntaxError.new("Expression exceeds nesting limit", expression: source)
      end

      return @plan.call(data) if config.equal?(@options) || configured_for?(config)

      evaluator = Evaluator.new(functions: config.functions, disable_visit_errors: config.disable_visit_errors)
      evaluator.evaluate(@root, data)
    end

    private

    def configured_for?(config)
      config.functions.equal?(@options.functions) && config.disable_visit_errors == @options.disable_visit_errors
    end
  end
end
