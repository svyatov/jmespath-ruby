# frozen_string_literal: true

require "pathname"
require "stringio"

module JMESPath
  # @api private
  module Input
    def self.load(data)
      case data
      when Pathname then File.open(data, "r", encoding: "UTF-8") { |file| JSON.parse(file.read) }
      when IO, StringIO then JSON.parse(data.read.to_s)
      else data
      end
    end
  end
end
