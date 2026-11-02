# frozen_string_literal: true

module JMESPath
  # @api private
  class FailureCapture
    KEY = :jmespath_failure_capture
    attr_reader :owned, :excluded

    def initialize
      @owned = {} # : Hash[StandardError, bool]
               .compare_by_identity
      @excluded = {} # : Hash[StandardError, bool]
                  .compare_by_identity
    end

    def self.run(&)
      previous = Thread.current[KEY]
      context = new
      Thread.current[KEY] = context
      begin
        context.result(&)
      ensure
        Thread.current[KEY] = previous
      end
    end

    def result
      SearchResult.new(value: yield, error: nil)
    rescue Errors::Error, JSON::ParserError, IOError, SystemCallError => e
      raise unless owned.key?(e) && !excluded.key?(e)

      SearchResult.new(value: nil, error: e)
    end

    def self.owned(error)
      context = Thread.current[KEY]
      context.owned[error] = true if context
      error
    end

    def self.application
      context = Thread.current[KEY]
      return yield unless context

      Thread.current[KEY] = nil
      begin
        yield
      rescue StandardError => e
        context.excluded[e] = true
        raise
      ensure
        Thread.current[KEY] = context
      end
    end

    def self.excluded?(error)
      context = Thread.current[KEY]
      context ? context.excluded.key?(error) : false
    end
  end
end
