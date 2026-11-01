# frozen_string_literal: true

module JMESPath
  # @api private
  class Cache
    def initialize(limit: 32, bytes: 1_048_576)
      raise ArgumentError, "Cache capacities must be positive" unless limit.positive? && bytes.positive?

      @limit = limit
      @budget = bytes
      @used = 0
      @entries = {}
      @mutex = Mutex.new
    end

    def fetch(source, max_depth:)
      return yield source if source.bytesize > @budget

      # @type var key: [String, Integer]
      key = [source.frozen? ? source : source.dup.freeze, max_depth].freeze
      cached = @mutex.synchronize { read(key) }
      return cached if cached

      value = yield key.first
      @mutex.synchronize { write(key, value) }
      value
    end

    private

    def read(key)
      value = @entries.delete(key)
      @entries[key] = value if value
      value
    end

    def write(key, value)
      @used -= key.first.bytesize if @entries.delete(key)
      evict_for(key.first.bytesize)
      @entries[key] = value
      @used += key.first.bytesize
    end

    def evict_for(size)
      @entries.each_key do |key|
        break if @entries.length < @limit && @used + size <= @budget

        @entries.delete(key)
        @used -= key.first.bytesize
      end
    end
  end
end
