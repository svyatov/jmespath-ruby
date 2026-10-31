# frozen_string_literal: true

require "json"

module JMESPath
  # @api private
  class Lexer
    SINGLE = {
      "[" => :lbracket, "]" => :rbracket, "{" => :lbrace, "}" => :rbrace,
      "(" => :lparen, ")" => :rparen, "," => :comma, ":" => :colon,
      "." => :dot, "*" => :star, "@" => :current, "&" => :expref,
      "|" => :pipe, "!" => :not, "<" => :lt, ">" => :gt
    }.freeze
    DOUBLE = {
      "[]" => :flatten, "[?" => :filter, "&&" => :and, "||" => :or,
      "==" => :eq, "!=" => :ne, "<=" => :lte, ">=" => :gte
    }.freeze
    WHITESPACE = [9, 10, 13, 32].freeze

    attr_reader :source

    def initialize(source, max_depth: 128)
      @source = source.encode(Encoding::UTF_8).freeze
      raise Encoding::InvalidByteSequenceError unless @source.valid_encoding?

      @index = 0
      @max_depth = max_depth
    rescue EncodingError
      raise Errors::SyntaxError, "Expression has invalid encoding"
    end

    def tokens
      # @type var result: Array[Token?]
      result = []
      result << next_token while @index < source.bytesize
      result << Token.new(:eof, nil, @index, @index)
      result.compact.freeze
    end

    private

    def next_token
      start = @index
      byte = source.getbyte(@index)
      return skip_whitespace if WHITESPACE.include?(byte)
      return quoted_token(start, byte) if [34, 39, 96].include?(byte)
      return word_token(start) if identifier_start?(byte)
      return number_token(start) if byte == 45 || digit?(byte)

      operator_token(start)
    end

    def skip_whitespace
      @index += 1
      nil
    end

    def word_token(start)
      @index += 1 while identifier_part?(source.getbyte(@index))
      Token.new(:identifier, source.byteslice(start...@index), start, @index)
    end

    def number_token(start)
      @index += 1 if source.getbyte(@index) == 45
      syntax!("Expected a digit", start) unless digit?(source.getbyte(@index))
      @index += 1 while digit?(source.getbyte(@index))
      Token.new(:number, source.byteslice(start...@index).to_i, start, @index)
    end

    def operator_token(start)
      pair = source.byteslice(start, 2)
      type = DOUBLE[pair]
      length = type ? 2 : 1
      type ||= SINGLE[source.byteslice(start, 1)]
      syntax!("Unexpected character", start) unless type
      @index += length
      Token.new(type, nil, start, @index)
    end

    def quoted_token(start, quote)
      @index += 1
      content_start = @index
      scan_quote(quote, start)
      content = source.byteslice(content_start...@index).to_s
      @index += 1
      value = decode(content, quote)
      Token.new(quote == 34 ? :identifier : :literal, value, start, @index)
    rescue JSON::ParserError => e
      syntax!("Invalid quoted value: #{e.message}", start)
    end

    def scan_quote(quote, start)
      while @index < source.bytesize
        return if source.getbyte(@index) == quote

        @index += source.getbyte(@index) == 92 ? 2 : 1
      end
      syntax!("Unterminated quoted value", start)
    end

    def decode(content, quote)
      return JSON.parse("\"#{content}\"") if quote == 34
      return content.gsub(/\\(['\\])/) { Regexp.last_match(1) } if quote == 39

      literal(content.gsub("\\#{96.chr}", 96.chr))
    end

    def literal(content)
      JSON.parse(content, max_nesting: @max_depth)
    rescue JSON::ParserError
      JSON.parse("\"#{content.lstrip}\"", max_nesting: @max_depth)
    end

    def identifier_start?(byte)
      byte && (byte.between?(65, 90) || byte.between?(97, 122) || byte == 95)
    end

    def identifier_part?(byte)
      identifier_start?(byte) || digit?(byte)
    end

    def digit?(byte)
      byte&.between?(48, 57)
    end

    def syntax!(message, position)
      raise Errors::SyntaxError.new(message, expression: source, position: position)
    end
  end
end
