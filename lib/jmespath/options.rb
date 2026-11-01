# frozen_string_literal: true

module JMESPath
  # @api private
  class Options
    # rubocop:disable-next Style/RedundantParentheses -- Type the empty hash before freezing it.
    EMPTY = (
      {} # : Hash[Symbol, value]
    ).freeze
    KEYS = %i[cache_expressions disable_visit_errors functions max_depth].freeze
    attr_reader :cache_expressions, :disable_visit_errors, :functions, :max_depth

    def initialize(positional = {}, keywords = {}, default_depth: 128, defaults: nil)
      values = merge(positional, keywords)
      @cache_expressions = boolean(values.fetch(:cache_expressions, true))
      @disable_visit_errors = boolean(values.fetch(:disable_visit_errors) do
        default_value(defaults, :disable_visit_errors)
      end)
      @max_depth = depth(values.fetch(:max_depth, default_depth))
      @functions = registry(values.fetch(:functions) { default_value(defaults, :functions) })
      freeze
    end

    private

    def default_value(defaults, name)
      return defaults.public_send(name) if defaults

      name == :functions ? Functions.default : false
    end

    def merge(positional, keywords)
      raise ArgumentError, "Options must be a Hash" unless positional.is_a?(Hash)

      keywords.each_key do |key|
        raise ArgumentError, "Conflicting option: #{key}" if positional.key?(key) && positional[key] != keywords[key]
      end
      values = positional.merge(keywords)
      raise ArgumentError, "Unknown search options" unless (values.keys - KEYS).empty?

      values
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

  Options::DEFAULT = Options.new
end
