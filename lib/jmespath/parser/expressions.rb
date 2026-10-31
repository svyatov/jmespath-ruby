# frozen_string_literal: true

module JMESPath
  # @api private
  class Parser
    private

    def prefix_identifier(token)
      node(:field, token.value, [], start: token.start)
    end

    def prefix_literal(token)
      node(:literal, token.value, [], start: token.start)
    end

    def prefix_current(token)
      node(:current, nil, [], start: token.start)
    end

    def prefix_group(token)
      inner = expression
      expect(:rparen)
      node(:group, nil, [inner], start: token.start)
    end

    def prefix_not(token)
      node(:not, nil, [expression(45)], start: token.start)
    end

    def prefix_reference(token)
      node(:expression_reference, nil, [expression], start: token.start)
    end

    def prefix_hash(token)
      pairs = separated(:rbrace) do
        key = expect(:identifier)
        expect(:colon)
        node(:pair, key.value, [expression], start: key.start)
      end
      node(:multi_select_hash, nil, pairs, start: token.start)
    end

    def multi_select_list(token)
      items = separated(:rbracket) { expression }
      node(:multi_select_list, nil, items, start: token.start)
    end

    def infix_function(left, token)
      unless left.kind == :field && @source.getbyte(left.start) != 34
        syntax!("Function name must be an unquoted identifier", token)
      end
      arguments = separated(:rparen, empty: true) { expression }
      node(:function, left.value, arguments, start: left.start)
    end

    def infix_dot(left, _token)
      return node(:value_projection, nil, [left, projection_rhs(20)]) if peek.type == :star && advance

      sequence(:subexpression, left, dot_rhs(40))
    end

    def dot_rhs(power)
      return multi_select_list(advance) if peek.type == :lbracket

      syntax!("Expected a field, function, or multiselect after dot") unless %i[identifier lbrace
                                                                                star].include?(peek.type)
      expression(power)
    end
  end
end
