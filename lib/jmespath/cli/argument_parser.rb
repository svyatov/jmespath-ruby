# frozen_string_literal: true

require "optparse"

module JMESPath
  module CLI
    # Avoid require_exact, which breaks equals values and delimiters on Ruby 3.3.
    # @api private
    class ArgumentParser < OptionParser
      def permute(argv)
        index = 0
        while (argument = argv[index])
          break if argument == "--"
          raise InvalidOption, argument if argument.match?(/\A--raw_output(?:=|\z)/)

          index += %w[--file --query-file --query_file].include?(argument) ? 2 : 1
        end
        super
      end

      private

      def complete(kind, name, *)
        switch = search(kind, name)
        raise InvalidOption, name unless switch

        [switch, name]
      end
    end
  end
end
