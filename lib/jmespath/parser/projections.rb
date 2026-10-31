# frozen_string_literal: true

module JMESPath
  # @api private
  class Parser
    private

    def prefix_bracket(token)
      return bracket_body(node(:current)) if %i[number colon star].include?(peek.type)

      multi_select_list(token)
    end

    def infix_bracket(left, _token)
      bracket_body(left)
    end

    def bracket_body(left)
      if peek.type == :star
        advance
        expect(:rbracket)
        return node(:projection, nil, [left, projection_rhs(20)])
      end
      index_or_slice(left)
    end

    def index_or_slice(left)
      start = integer if peek.type == :number
      return slice(left, start) if peek.type == :colon

      syntax!("Expected an array index") unless start
      expect(:rbracket)
      node(:index, start, [left])
    end

    def slice(left, start)
      advance
      stop = integer if peek.type == :number
      step = slice_step
      expect(:rbracket)
      raise Errors::InvalidValueError, "Slice step cannot be zero" if step&.zero?

      base = node(:slice, [start, stop, step], [left])
      node(:projection, nil, [base, projection_rhs(20)])
    end

    def slice_step
      return nil unless peek.type == :colon

      advance
      integer if peek.type == :number
    end

    def integer
      advance.value.to_s.to_i
    end

    def prefix_star(_token)
      node(:value_projection, nil, [node(:current), projection_rhs(20)])
    end

    def prefix_flatten(token)
      infix_flatten(node(:current), token)
    end

    def infix_flatten(left, _token)
      base = node(:flatten, nil, [left])
      node(:projection, nil, [base, projection_rhs(9)])
    end

    def prefix_filter(token)
      infix_filter(node(:current), token)
    end

    def infix_filter(left, _token)
      condition = expression
      expect(:rbracket)
      node(:filter_projection, nil, [left, projection_rhs(21), condition])
    end

    def projection_rhs(power)
      return node(:current) if POWER.fetch(peek.type, 0) < 10
      return expression(power) if peek.type == :lbracket
      return dot_rhs(power) if peek.type == :dot && advance

      syntax!("Invalid projection")
    end
  end
end
