# frozen_string_literal: true

module JMESPath
  # Plain-text presentation of query syntax failures.
  module Diagnostic
    class << self
      # Format a syntax failure without reading data or printing output.
      # @param error [Errors::SyntaxError, SyntaxDiagnostic] the syntax failure
      # @return [String] UTF-8 diagnostic without a trailing newline
      # @example Format a located failure
      #   error = JMESPath::Errors::SyntaxError.new("Bad query", expression: "$", position: 0)
      #   JMESPath::Diagnostic.format(error) #=> "Bad query at line 1, column 1\n$\n^"
      def format(error)
        reason = render(error.reason.encode(Encoding::UTF_8, invalid: :replace, undef: :replace))
        parts = source_parts(error)
        return reason unless parts

        located(reason, parts[0], parts[1])
      end

      private

      def located(reason, source, prefix)
        line = prefix.count("\n") + 1
        line_prefix = prefix.rpartition("\n").last
        excerpt = source.split("\n", -1).fetch(line - 1, "")
        caret = "#{' ' * render(line_prefix).length}^"
        "#{reason} at line #{line}, column #{line_prefix.length + 1}\n#{render(excerpt)}\n#{caret}"
      end

      def source_parts(error)
        source = error.expression
        position = error.position
        return unless position&.between?(0, source.bytesize) && error.location_known?

        prefix = source.byteslice(0, position).to_s
        return unless source.valid_encoding? && prefix.valid_encoding?

        [source.encode(Encoding::UTF_8), prefix.encode(Encoding::UTF_8)]
      rescue EncodingError
        nil
      end

      def render(line)
        column = 0
        line.each_char.with_object(+"") do |character, result|
          text = render_character(character, column)
          result << text
          column += text.length
        end
      end

      def render_character(character, column)
        return " " * (4 - (column % 4)) if character == "\t"
        return character.dump[1...-1].to_s if character.ord < 32 || character.ord == 127

        character
      end
    end
  end
end
