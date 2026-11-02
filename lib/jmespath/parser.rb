# frozen_string_literal: true

module JMESPath
  # @api private
  class Parser
    POWER = {
      pipe: 1, or: 2, and: 3, eq: 5, ne: 5, lt: 5, lte: 5, gt: 5, gte: 5,
      flatten: 9, filter: 21, dot: 40, lbracket: 55, lparen: 60
    }.freeze
    PREFIX = {
      identifier: :prefix_identifier, literal: :prefix_literal, current: :prefix_current,
      lparen: :prefix_group, lbracket: :prefix_bracket, lbrace: :prefix_hash,
      not: :prefix_not, expref: :prefix_reference, star: :prefix_star,
      flatten: :prefix_flatten, filter: :prefix_filter
    }.freeze
    INFIX = {
      dot: :infix_dot, lbracket: :infix_bracket, lparen: :infix_function,
      flatten: :infix_flatten, filter: :infix_filter
    }.freeze

    def initialize(source, max_depth: 128)
      raise ArgumentError, "max_depth must be an integer from 1 through 128" unless (1..128).cover?(max_depth)

      lexer = Lexer.new(source, max_depth: max_depth)
      @source = lexer.source
      @tokens = lexer.tokens
      @index = 0
      @level = 0
      @max_depth = max_depth
    end

    def parse
      result = expression
      expect(:eof)
      result
    end

    private

    def expression(power = 0)
      @level += 1
      syntax!("Expression exceeds nesting limit") if @level > @max_depth + 1
      token = advance
      method = PREFIX[token.type]
      syntax!("Expected an expression", token) unless method
      left = send(method, token)
      left = infix(left, advance) while power < POWER.fetch(peek.type, 0)
      left
    ensure
      @level -= 1
    end

    def infix(left, token)
      method = INFIX[token.type]
      return send(method, left, token) if method

      right = expression(POWER.fetch(token.type))
      return sequence(token.type, left, right) if %i[pipe and or].include?(token.type)

      node(token.type, nil, [left, right])
    end

    def sequence(kind, left, right)
      children = left.kind == kind ? [*left.children, right] : [left, right]
      node(kind, nil, children)
    end

    def node(kind, value = nil, children = [], start: nil, synthetic: false)
      result = AST::Node.new(
        kind: kind, value: value, children: children,
        start: start || children.first&.start || previous.start, finish: previous.finish, synthetic: synthetic
      )
      syntax!("Expression exceeds nesting limit") if result.depth > @max_depth
      result
    end

    def peek
      @tokens.fetch(@index)
    end

    def previous
      @tokens.fetch([@index - 1, 0].max)
    end

    def advance
      token = peek
      @index += 1 unless token.type == :eof
      token
    end

    def expect(type)
      token = advance
      syntax!("Expected #{type}, received #{token.type}", token) unless token.type == type
      token
    end

    def separated(terminator, empty: false)
      # @type var result: Array[AST::Node]
      result = []
      unless empty && peek.type == terminator
        loop do
          result << yield
          break unless peek.type == :comma

          advance
        end
      end
      expect(terminator)
      result
    end

    def syntax!(message, token = peek)
      raise Errors::SyntaxError.new(message, expression: @source, position: token.start)
    end
  end
end

require_relative "parser/expressions"
require_relative "parser/projections"
