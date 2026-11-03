# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InteractiveKeyStroke < Reline::KeyStroke
      # @api private
      class InvalidInput < StandardError
        attr_reader :byte

        def initialize(byte)
          @byte = byte
          super("Invalid UTF-8 query")
        end

        def ended?
          [4, 10, 13].include?(@byte)
        end
      end

      def match_status(input)
        validate_prefix(input)
        super
      end

      def expand(input)
        keys, rest = super
        keys = keys.map do |key|
          case key.method_symbol
          when :bracketed_paste_start
            Reline::Key.new(read_paste, :insert_multiline_text)
          when :quoted_insert, :ed_quoted_insert
            Reline::Key.new(read_quoted, :insert_raw_char)
          else
            key
          end
        end
        [keys, rest]
      end

      private

      def validate_prefix(input)
        decoder = Encoding::Converter.new("UTF-8", "UTF-16LE")
        source = input.pack("C*")
        status = decoder.primitive_convert(source, +"", nil, nil, Encoding::Converter::PARTIAL_INPUT)
        raise InvalidInput, input.fetch(-1) unless status == :source_buffer_empty
      end

      def read_paste
        marker = "\e[201~".b
        buffer = +"".b
        until buffer.end_with?(marker)
          byte = Reline::IOGate.getc(Float::INFINITY)
          break unless byte

          buffer << byte
        end
        text = buffer.delete_suffix(marker).force_encoding(Encoding::UTF_8)
        raise InvalidInput, 255 unless text.valid_encoding?

        text
      end

      def read_quoted
        # @type var bytes: Array[Integer]
        bytes = []
        loop do
          byte = Reline::IOGate.getc(Float::INFINITY)
          return "" unless byte

          bytes << byte
          validate_prefix(bytes)
          text = bytes.pack("C*").force_encoding(Encoding::UTF_8)
          return text if text.valid_encoding?
        end
      end
    end
  end
end
