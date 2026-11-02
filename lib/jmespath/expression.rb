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
      @plan = Plan.build(root, options) { |native_functions| @native_functions = native_functions }
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

    # Search input and require a non-null result.
    # @param data [Object] the same input forms accepted by {#search}
    # @param options [Hash] positional evaluation options
    # @param keywords [Hash] keyword evaluation options
    # @return [Object] the query result, excluding nil
    # @raise [Errors::NullResultError] evaluation returned nil
    # @example Require a user's name
    #   JMESPath.compile("user.name").fetch({user: {name: "Ada"}}) #=> "Ada"
    def fetch(data, options = Options::EMPTY, **keywords)
      value = search(data, options, **keywords)
      raise Errors::NullResultError.new(expression: source) if value.nil?

      value
    end

    # Explain query structure without evaluating input or resolving functions.
    # @return [Hash] deeply frozen source text and logical operation tree
    # @example Inspect a field chain
    #   JMESPath.compile("user.name").explain[:root][:operation] #=> "subexpression"
    def explain
      Explanation.build(source, @root)
    end

    # Evaluate once with bounded diagnostics for null fields and omitted items.
    # @param data [Object] the same input forms accepted by {#search}
    # @param options [Hash] positional evaluation options
    # @param limit [Integer] positive maximum number of retained events
    # @param keywords [Hash] keyword evaluation options
    # @return [Hash] frozen report with value, events, and truncated
    # @raise [ArgumentError] limit or evaluation options are invalid
    # @example Trace a missing field
    #   JMESPath.compile("name").trace({})[:events].first[:type] #=> "field_null"
    def trace(data, options = Options::EMPTY, limit: 1000, **keywords)
      raise ArgumentError, "limit must be a positive Integer" unless limit.is_a?(Integer) && limit.positive?

      fast = options.equal?(Options::EMPTY) && keywords.empty?
      config = fast ? @options : Options.new(options, keywords, default_depth: @max_depth, defaults: @options)
      collector = Tracing::Collector.new(root: @root, limit: limit)
      collector.finish(trace_value(trace_input(data, fast), config, collector))
    ensure
      collector&.close
    end

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

    def trace_input(data, fast)
      return data if fast && data.is_a?(Hash)

      Input.load(data)
    end

    def trace_value(data, config, collector)
      if @root.depth > config.max_depth
        raise Errors::SyntaxError.new("Expression exceeds nesting limit", expression: source)
      end

      evaluator = Tracing::Evaluator.new(config: config, collector: collector, root: @root,
                                         planned: configured_for?(config), native_functions: @native_functions)
      evaluator.evaluate(@root, data)
    end

    def configured_for?(config)
      config.functions.equal?(@options.functions) && config.disable_visit_errors == @options.disable_visit_errors
    end
  end
end
