# frozen_string_literal: true

require_relative "interactive_editor_state"
require_relative "interactive_completion"

module JMESPath
  module CLI
    # @api private
    class InteractiveEditor
      HISTORY_LIMIT = 500

      def self.supported?(input:, errors:)
        return false unless terminal_environment?

        return false unless [input, errors].all? { |stream| stream.is_a?(IO) && !stream.closed? && stream.tty? }

        require "io/console"
        true
      end

      def self.terminal_environment?
        ![nil, "", "dumb"].include?(ENV.fetch("TERM", nil)) && !ENV.key?("RELINE_STDERR_TTY")
      end

      def initialize(input:, errors:)
        @input = input
        @errors = errors
        @history = []
        @pending = []
        @completion = InteractiveCompletion.new
        @writing_errors = false
      end

      def open
        require "reline"
        state = InteractiveEditorState.new
        begin
          state.configure(@input, @errors)
          Reline.completion_proc = method(:complete)
          yield
        ensure
          state.restore
        end
      end

      def gets
        return @pending.shift unless @pending.empty?

        @writing_errors = true
        line = Reline.readline("jmespath> ", false)
        @writing_errors = false
        return unless line

        lines = Reline.core.line_editor.whole_lines
        return line if lines.length == 1

        @pending = lines
        @pending.shift
      rescue Interrupt
        @errors.puts("^C")
        retry
      end

      def remember(query)
        @history << query
        @history.shift if @history.length > HISTORY_LIMIT
        Reline::HISTORY.replace(@history)
      end

      def writing_errors?
        @writing_errors
      end

      private

      def complete(_target)
        line = Reline.line_buffer
        result = @completion.complete(line, point: Reline.point)
        if result[:line] != line
          Reline.delete_text
          Reline.insert_text(result[:line])
          Reline.point = result[:point]
        elsif result[:candidates].length > 1
          @errors.puts("\n#{result[:candidates].join('  ')}")
        end
        nil
      end
    end
  end
end
