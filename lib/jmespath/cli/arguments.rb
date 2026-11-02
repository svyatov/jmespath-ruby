# frozen_string_literal: true

require_relative "argument_parser"

module JMESPath
  # Executes queries, validates syntax, or lists built-in functions.
  module CLI
    # @api private
    def self.literal_validation?(argv)
      argv.first == "--validate" && argv.length == 2
    end

    # @api private
    def self.parse_arguments(argv)
      return [argv.fetch(0), nil, nil, false, false, false, false] if argv.one? && !argv.fetch(0).start_with?("-")

      paths = {} # : Hash[String, String]
      arguments = argument_parser(paths).permute(argv)
      check_sources(arguments, paths)

      [arguments.first, paths["file"], paths["query-file"], paths.key?("validate"), paths.key?("pretty"),
       paths.key?("raw-output"), paths.key?("json-lines")]
    end

    # @api private
    def self.check_sources(arguments, paths)
      sources = arguments.length + (paths.key?("query-file") ? 1 : 0)
      raise OptionParser::InvalidArgument, "expected one query source" unless sources == 1

      check_modes(paths)
    end

    # @api private
    def self.check_modes(paths)
      modes = paths.keys & %w[validate pretty raw-output json-lines]
      raise OptionParser::InvalidArgument, "conflicting modes" if modes.length > 1
      return unless paths.key?("validate")
      return if paths.key?("query-file") && !paths.key?("file")

      raise OptionParser::InvalidArgument, "validation requires a query file"
    end

    # @api private
    def self.argument_parser(paths)
      ArgumentParser.new do |options|
        options.on("-h", "--help", "--version", "--functions", "--*-completion-bash", "--*-completion-zsh") do
          raise OptionParser::InvalidOption, "unsupported option combination"
        end
        %w[file query-file].each do |name|
          options.on("--#{name} PATH") do |value|
            raise OptionParser::InvalidOption, "--#{name} repeated" if paths.key?(name)

            paths[name] = value
          end
        end
        %w[validate pretty raw-output json-lines].each do |name|
          options.on("--#{name}") do
            raise OptionParser::InvalidOption, "--#{name} repeated" if paths.key?(name)

            paths[name] = ""
          end
        end
      end
    end
  end
end
