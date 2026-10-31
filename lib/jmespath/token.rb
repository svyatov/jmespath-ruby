# frozen_string_literal: true

module JMESPath
  # @api private
  Token = Data.define(:type, :value, :start, :finish)
end
