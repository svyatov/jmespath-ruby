# frozen_string_literal: true

module JMESPath
  # @api private
  class Cache
    def initialize(limit: 256, bytes: 1_048_576)
      raise ArgumentError, "Cache capacities must be positive" unless limit.positive? && bytes.positive?

      @limit = limit
      @budget = bytes
      @used = 0
      @entries = {}
      @mutex = Mutex.new
    end

    def fetch(source, max_depth:)
      return yield if source.bytesize > @budget

      # @type var key: [String, Integer]
      key = [source.frozen? ? source : source.dup.freeze, max_depth].freeze
      cached = @mutex.synchronize { read(key) }
      return cached if cached

      value = yield
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
      while @entries.length >= @limit || @used + size > @budget
        entry = @entries.shift
        break unless entry

        @used -= entry.first.first.bytesize
      end
    end
  end
end
