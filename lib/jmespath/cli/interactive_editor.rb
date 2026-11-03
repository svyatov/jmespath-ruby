# frozen_string_literal: true

require_relative "interactive_editor_state"

module JMESPath
  module CLI
    # @api private
    class InteractiveEditor
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
        Reline.readline("jmespath> ", false)
      rescue Interrupt
        @errors.puts("^C")
        retry
      end
    end
  end
end
