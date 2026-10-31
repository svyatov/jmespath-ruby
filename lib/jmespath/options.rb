# frozen_string_literal: true

module JMESPath
  # @api private
  class Options
    KEYS = %i[cache_expressions disable_visit_errors functions max_depth].freeze
    attr_reader :cache_expressions, :disable_visit_errors, :functions, :max_depth

    def initialize(positional = {}, keywords = {}, default_depth: 128)
      values = merge(positional, keywords)
      raise ArgumentError, "Unknown search options" unless (values.keys - KEYS).empty?

      @cache_expressions = boolean(values.fetch(:cache_expressions, true))
      @disable_visit_errors = boolean(values.fetch(:disable_visit_errors, false))
      @max_depth = depth(values.fetch(:max_depth, default_depth))
      @functions = registry(values.fetch(:functions, Functions.default))
      freeze
    end

    private

    def merge(positional, keywords)
      raise ArgumentError, "Options must be a Hash" unless positional.is_a?(Hash)

      keywords.each_key do |key|
        raise ArgumentError, "Conflicting option: #{key}" if positional.key?(key) && positional[key] != keywords[key]
      end
      positional.merge(keywords)
    end

    def boolean(value)
      case value
      when TrueClass, FalseClass then value
      else raise ArgumentError, "Expected a boolean option"
      end
    end

    def depth(value)
      unless value.is_a?(Integer) && (1..128).cover?(value)
        raise ArgumentError, "max_depth must be an integer from 1 through 128"
      end

      value
    end

    def registry(value)
      raise ArgumentError, "functions must be a Functions registry" unless value.is_a?(Functions)

      value
    end
  end
end
