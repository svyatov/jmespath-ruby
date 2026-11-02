# frozen_string_literal: true

module JMESPath
  # @api private
  class Normalizer
    def initialize(key: nil, &scalar)
      @pending = []
      @active = {}
      @scalar = scalar
      @key = key
    end

    def call(value)
      # @type var result: Array[value]
      result = [nil]
      enqueue(value) { |entry| result[0] = entry }
      while (operation = @pending.pop)
        operation.call
      end
      result.first
    end

    private

    def enqueue(value, &assign)
      @pending << -> { visit(value, &assign) }
    end

    def visit(value, &assign)
      collection = DataAccess.array(value) || DataAccess.object(value)
      return assign.call(scalar(value)) unless collection

      id = activate(value)
      @pending << -> { @active.delete(id) }
      collection.is_a?(Array) ? array(collection, &assign) : object(collection, &assign)
    end

    def scalar(value)
      value = DataAccess.string(value) || value
      transform = @scalar
      transform ? transform.call(value) : value
    end

    def activate(value)
      id = value.object_id
      if @active[id]
        raise FailureCapture.owned(Errors::InvalidValueError.new("Cyclic values cannot be compared or serialized"))
      end

      @active[id] = true
      id
    end

    def array(values)
      # @type var result: Array[value]
      result = Array.new(values.length)
      yield result
      (values.length - 1).downto(0) { |index| enqueue(values[index]) { |entry| result[index] = entry } }
    end

    def object(values)
      # @type var result: Hash[value, value]
      result = values.transform_values { nil }
      yield result
      transform = @key
      @pending << -> { result.transform_keys!(&transform) } if transform
      values.to_a.reverse_each { |key, value| enqueue(value) { |entry| result[key] = entry } }
    end
  end
end
