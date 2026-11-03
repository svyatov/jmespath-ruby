# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InteractiveEditorState
      CALLBACKS = %i[completion_proc output_modifier_proc prompt_proc auto_indent_proc pre_input_hook
                     dig_perfect_match_proc].freeze

      def initialize
        @core = Reline.core
        # Reline 0.7 exposes only input=; retain the previous reader for restoration.
        @input = Reline::IOGate.instance_variable_get(:@input)
        @output = @core.output
        @configuration = [@core.config, @core.key_stroke, @core.line_editor]
        @callbacks = CALLBACKS.to_h { |key| [key, Reline.public_send(key)] }
        @history = Reline::HISTORY.to_a
      end

      def configure(input, errors)
        Reline.input = input
        Reline.output = errors
        configure_core
        CALLBACKS.each { |key| Reline.public_send(:"#{key}=", nil) }
        Reline::HISTORY.clear
      end

      def configure_core
        config = Reline::Config.new
        config.read
        Reline::IOGate.set_default_key_bindings(config)
        @core.config = config
        @core.key_stroke = Reline::KeyStroke.new(config, Reline::IOGate.encoding)
        @core.line_editor = Reline::LineEditor.new(config)
      end

      def restore
        Reline.input = @input
        Reline.output = @output
        @core.config, @core.key_stroke, @core.line_editor = @configuration
        @callbacks.each { |key, value| Reline.public_send(:"#{key}=", value) }
        Reline::HISTORY.replace(@history)
      end
    end
  end
end
