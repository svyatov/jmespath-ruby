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
        decoder = Encoding::Converter.new("UTF-8", "UTF-16LE")
        source = input.pack("C*")
        status = decoder.primitive_convert(source, +"", nil, nil, Encoding::Converter::PARTIAL_INPUT)
        raise InvalidInput, input.fetch(-1) unless status == :source_buffer_empty

        super
      end
    end
  end
end
