# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InteractiveCompletion
      def initialize(functions: Functions.default)
        @names = functions.names.sort
      end

      def complete(line, point:)
        # @type var unchanged: completion_result
        unchanged = { line: line, point: point, candidates: [] }
        token = token(line, point)
        return unchanged unless token

        prefix, start, finish = token
        names = @names.select { |name| name.start_with?(prefix) }
        unchanged[:candidates] = names
        return unchanged if names.empty?

        common = common_prefix(names)
        return unchanged if names.length > 1 && common == prefix

        { line: replace(line, start, finish, common),
          point: start + common.bytesize, candidates: names }
      end

      private

      def replace(line, start, finish, common)
        line.byteslice(0, start).to_s + common + line.byteslice(finish..).to_s
      end

      def token(line, point)
        return unless valid_cursor?(line, point)

        before = line.byteslice(0, point).to_s
        return if quoted?(before)

        prefix = identifier_prefix(before)
        return unless prefix&.match?(/\A[A-Za-z_]/)

        suffix = line.byteslice(point..).to_s[/\A[A-Za-z0-9_]*/].to_s
        [prefix, point - prefix.bytesize, point + suffix.bytesize]
      end

      def identifier_prefix(before)
        before.reverse[/\A[A-Za-z0-9_]+/]&.reverse
      end

      def valid_cursor?(line, point)
        source = line.dup.force_encoding(Encoding::UTF_8)
        return false unless source.valid_encoding? && point.between?(0, source.bytesize)
        return false unless source.byteslice(0, point).to_s.valid_encoding?
        return false if source.include?("\n")

        query?(source, point)
      end

      def query?(line, point)
        return true unless line.match?(/\A[ \t]*:/)

        command = /\A[ \t]*:(?:explain|trace)[ \t]+/.match(line)
        return false unless command

        point >= command[0].bytesize
      end

      def quoted?(before)
        index = 0
        quote = nil
        while index < before.bytesize
          byte = before.getbyte(index)
          if quote
            index += 1 if byte == 92
            quote = nil if byte == quote
          elsif [34, 39, 96].include?(byte)
            quote = byte
          end
          index += 1
        end
        !quote.nil?
      end

      def common_prefix(names)
        common = names.fetch(0)
        common = common[0...-1] until names.fetch(-1).start_with?(common)
        common
      end
    end
  end
end
