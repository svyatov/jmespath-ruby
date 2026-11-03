# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InteractiveSession
      HELP = "Enter one query per line; blank lines are ignored.\n:help shows help; :quit ends the session.\n" \
             ":functions lists built-ins; :explain QUERY shows structure without evaluating the document.\n" \
             "Supported terminals provide editing and recall of the last 500 queries for this session only.\n" \
             "Ctrl-C cancels the current edit. Other streams use the plain line reader.\n" \
             "Tab completes function names outside quotes; ambiguous prefixes list sorted names.\n" \
             "Prompts and diagnostics use stderr; successful JSON results use stdout."

      def initialize(data, input:, output:, errors:)
        @data = data
        @input = input
        @output = output
        @errors = errors
        @writing_errors = false
      end

      def run
        if InteractiveEditor.supported?(input: @input, errors: @errors)
          editor = InteractiveEditor.new(input: @input, errors: @errors)
          @editor = editor
          editor.open { read_queries }
        else
          read_queries
        end
      rescue IOError, SystemCallError => e
        report_stream_failure(e)
        1
      end

      private

      def read_queries
        loop do
          prompt unless @editor
          editor = @editor
          line = editor ? editor.gets : @input.gets
          break unless line
          break if process?(line)
        end
        0
      end

      def process?(line)
        expression = line.dup.force_encoding(Encoding::UTF_8)
        unless expression.valid_encoding?
          diagnostic("Invalid UTF-8 query")
          return false
        end
        expression = expression.sub(/\r?\n\z/, "")
        command = expression.gsub(/\A[ \t]+|[ \t]+\z/, "")
        command?(command, expression)
      end

      def command?(command, expression)
        return true if command == ":quit"
        return false if command.empty?

        if command == ":help"
          diagnostic(HELP)
        elsif command.start_with?(":")
          diagnostic(InteractiveCommands.call(expression))
        else
          @editor&.remember(expression)
          result = evaluate(expression)
          write_result(result) if result
        end
        false
      end

      def evaluate(expression)
        JSON.generate(JMESPath.search(expression, @data))
      rescue JSON::NestingError
        diagnostic("Invalid JSON result")
        nil
      rescue Errors::Error, JSON::GeneratorError => e
        diagnostic(FailureDiagnostic.format(e, expression))
        nil
      end

      def write_result(result)
        @output.puts(result)
        flush(@output)
      end

      def diagnostic(text)
        @writing_errors = true
        @errors.puts(text)
        flush(@errors)
        @writing_errors = false
      end

      def prompt
        # @type var input: Object & _TerminalReader
        input = @input
        return unless input.respond_to?(:tty?) && input.tty?

        @writing_errors = true
        # @type var errors: _PromptWriter
        errors = @errors
        errors.print("jmespath> ")
        errors.flush
        @writing_errors = false
      end

      def flush(stream)
        # @type var output: Object & _Flushable
        output = stream
        output.flush if output.respond_to?(:flush)
      end

      def report_stream_failure(error)
        return if @writing_errors || @editor&.writing_errors?

        diagnostic(FailureDiagnostic.format(error, nil))
      rescue IOError, SystemCallError
        nil
      end
    end
  end
end
