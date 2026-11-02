# frozen_string_literal: true

module JMESPath
  # @api private
  module Tracing
    # @api private
    class Collector
      def initialize(root:, limit:)
        @ids = {} # : Hash[AST::Node, Integer]
               .compare_by_identity
        index(root)
        @limit = limit
        @events = []
        @contexts = {}
        @references = {}
        @truncated = false
        @closed = false
        @mutex = Mutex.new
      end

      def operation_id(node)
        @ids.fetch(node)
      end

      def within(node, index)
        thread = Thread.current
        stack = @mutex.synchronize do
          unless @closed
            context = (@contexts[thread] ||= [])
            # @type var frame: trace_context
            frame = { operation_id: operation_id(node), index: index }.freeze
            context << frame
            context
          end
        end
        return yield unless stack

        begin
          yield
        ensure
          @mutex.synchronize do
            stack.pop
            @contexts.delete(thread) if stack.empty?
          end
        end
      end

      def reference(node, &)
        index = @mutex.synchronize do
          unless @closed
            id = operation_id(node)
            count = @references.fetch(id, 0)
            @references[id] = count + 1
            count
          end
        end
        return yield if index.nil?

        within(node, index, &)
      end

      def emit(type, node, details = {})
        @mutex.synchronize do
          return if @closed

          if @events.length >= @limit
            @truncated = true
            return
          end
          # @type var event: trace_event
          event = {
            type: type.dup.freeze, operation_id: operation_id(node),
            context: @contexts.fetch(Thread.current, []).dup.freeze,
            details: details.transform_values { |value| value.dup.freeze }.freeze
          }.freeze
          @events << event
        end
      end

      def finish(value)
        @mutex.synchronize do
          # @type var report: trace_report
          report = { value: value, events: @events.freeze, truncated: @truncated }.freeze
          clear
          report
        end
      end

      def close
        @mutex.synchronize { clear }
      end

      private

      def index(node)
        @ids[node] = @ids.length
        Explanation.syntax_children(node).each { |child| index(child) }
      end

      def clear
        @closed = true
        @ids.clear
        @contexts.clear
        @references.clear
        @events = []
      end
    end
  end
end
