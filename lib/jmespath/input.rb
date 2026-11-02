# frozen_string_literal: true

require "pathname"
require "stringio"

module JMESPath
  # @api private
  module Input
    def self.load(data)
      return data if data.is_a?(Hash) || data.is_a?(Array) || data.is_a?(Struct)
      return captured_load(data) if FailureCapture.active?

      case data
      when Pathname then File.open(data, "r", encoding: "UTF-8") { |file| JSON.parse(file.read) }
      when IO, StringIO then JSON.parse(data.read.to_s)
      else data
      end
    end

    def self.captured_load(data)
      case data
      when Pathname then load_file(data)
      when IO, StringIO
        text = read(data)
        parse(FailureCapture.application { text.to_s })
      else data
      end
    end

    def self.load_file(data)
      path = FailureCapture.application { data.to_path }
      raise TypeError, "to_path must return String" unless path.is_a?(String)

      File.open(path, "r", encoding: "UTF-8") { |file| parse(read(file)) }
    rescue IOError, SystemCallError => e
      raise FailureCapture.owned(e)
    end

    def self.read(data)
      return FailureCapture.application { data.read } unless native_read?(data)

      data.read
    rescue IOError, SystemCallError => e
      raise FailureCapture.owned(e)
    end

    def self.native_read?(data)
      reader = Kernel.instance_method(:method).bind_call(data, :read)
      [IO, StringIO].include?(reader.owner) && reader.source_location.nil?
    end

    def self.parse(text)
      JSON.parse(text)
    rescue JSON::ParserError => e
      raise FailureCapture.owned(e)
    end
  end
end
