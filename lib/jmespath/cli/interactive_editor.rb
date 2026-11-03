# frozen_string_literal: true

require_relative "interactive_editor_state"

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
      end

      def open
        require "reline"
        state = InteractiveEditorState.new
        begin
          state.configure(@input, @errors)
          yield
        ensure
          state.restore
        end
      end

      def gets
        return @pending.shift unless @pending.empty?

        line = Reline.readline("jmespath> ", false)
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
    end
  end
end
