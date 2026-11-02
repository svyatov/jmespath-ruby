# frozen_string_literal: true

require_relative "jmespath/version"
require_relative "jmespath/errors"
require_relative "jmespath/diagnostic"
require_relative "jmespath/token"
require_relative "jmespath/lexer"
require_relative "jmespath/expression_reference"
require_relative "jmespath/data_access"
require_relative "jmespath/types"
require_relative "jmespath/ast"
require_relative "jmespath/parser"
require_relative "jmespath/functions"
require_relative "jmespath/functions/suggestions"
require_relative "jmespath/evaluator"
require_relative "jmespath/functions/scalar"
require_relative "jmespath/functions/collections"
require_relative "jmespath/functions/function_call"
require_relative "jmespath/options"
require_relative "jmespath/input"
require_relative "jmespath/cache"
require_relative "jmespath/plan"
require_relative "jmespath/explanation"
require_relative "jmespath/expression"
require_relative "jmespath/tracing/collector"

# Search JSON-compatible Ruby values with JMESPath expressions.
module JMESPath
  # @api private
  CACHE = Cache.new
  private_constant :CACHE

  class << self
    # Search Ruby data using a JMESPath expression.
    # @param expression [String] query text
    # @param data [Object] Ruby values, Pathname, IO, or StringIO
    # @param options [Hash] positional compatibility options
    # @param keywords [Hash] keyword evaluation options
    # @option options [Boolean] :cache_expressions (true) reuse cached syntax
    # @option options [Boolean] :disable_visit_errors (false) suppress argument type and arity failures
    # @option options [Functions] :functions (Functions.default) registry for this search
    # @option options [Integer] :max_depth (128) maximum expression nesting
    # @raise [ArgumentError] options or expression type are invalid
    # @raise [Errors::Error] the query cannot be parsed or evaluated
    # @example Project a field from each item
    #   JMESPath.search("items[*].name", {items: [{name: "Ada"}]}) #=> ["Ada"]
    # @return [Object] the query result, including nil
    def search(expression, data, options = Options::EMPTY, **keywords)
      config = if options.equal?(Options::EMPTY) && keywords.empty?
                 Options::DEFAULT
               else
                 Options.new(options, keywords)
               end
      raise ArgumentError, "Expression must be a String" unless expression.is_a?(String)

      compiled = compile_syntax(expression, config.cache_expressions, config.max_depth)
      compiled.evaluate(Input.load(data), config)
    end

    # Parse an expression for repeated searches.
    # @param expression [String] query text
    # @param cache_expressions [Boolean] reuse bounded cached syntax
    # @param max_depth [Integer] maximum nesting from 1 through 128
    # @param functions [Functions] default registry for searches with this expression
    # @param disable_visit_errors [Boolean] default suppression of argument type and arity failures
    # @raise [ArgumentError] expression type or options are invalid
    # @raise [Errors::SyntaxError] the expression is invalid or exceeds its nesting limit
    # @example Reuse parsed syntax
    #   JMESPath.compile("name").search({name: "Ada"}) #=> "Ada"
    # @return [Expression] immutable reusable syntax
    def compile(expression, cache_expressions: true, max_depth: 128,
                functions: Functions.default, disable_visit_errors: false)
      raise ArgumentError, "Expression must be a String" unless expression.is_a?(String)

      config = compilation_options(cache_expressions, max_depth, functions, disable_visit_errors)
      compiled = compile_syntax(expression, cache_expressions, max_depth)
      config.equal?(Options::DEFAULT) ? compiled : compiled.configured(config)
    end

    private

    def compile_syntax(expression, cache, depth)
      if cache
        CACHE.fetch(expression, max_depth: depth) { |source| build_expression(source, depth) }
      else
        build_expression(expression, depth)
      end
    end

    def compilation_options(cache, depth, functions, suppress)
      if cache.equal?(true) && depth.equal?(128) && functions.equal?(Functions.default) && suppress.equal?(false)
        return Options::DEFAULT
      end

      Options.new({ cache_expressions: cache, max_depth: depth,
                    functions: functions, disable_visit_errors: suppress })
    end

    def build_expression(expression, max_depth)
      source = expression.dup.freeze
      Expression.new(source, Parser.new(source, max_depth: max_depth).parse, max_depth: max_depth)
    end
  end
end
