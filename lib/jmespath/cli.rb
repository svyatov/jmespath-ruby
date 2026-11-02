# frozen_string_literal: true

require_relative "../jmespath"
require_relative "cli/failure_diagnostic"
require_relative "cli/argument_parser"

module JMESPath
  # Executes queries as JSON or raw strings, or validates query syntax.
  module CLI
    USAGE = "Usage: jmespath [--pretty | --raw-output] [--file PATH] (EXPRESSION | --query-file PATH)\n       " \
            "jmespath --validate (EXPRESSION | --query-file PATH)"
    HELP = "#{USAGE}\n" \
           "Read one UTF-8 JSON document from --file PATH, or stdin when omitted.\n" \
           "Supply one query as EXPRESSION or --query-file PATH, read as UTF-8 without trimming.\n" \
           "Options may precede or follow EXPRESSION; -- ends option parsing.\n" \
           "Quote spaces: --file 'my document.json'. Use --file=--document.json for option-like names.\n" \
           "Paths are literal: --file - reads the file named -.\n" \
           "Query paths follow the same rules: --query-file - reads the query file named -.\n" \
           "Output is compact JSON by default; --pretty uses two-space indentation and a final newline.\n" \
           "Use --raw-output for literal string results; other results remain compact JSON.\n" \
           "Raw strings retain all their newlines and receive one additional output newline.\n" \
           "Output flags cannot be repeated or combined with each other or --validate.\n" \
           "Function arguments and expression-reference results are validated; failures exit with status 1.\n" \
           "Unknown functions suggest similar registered names.\n" \
           "Query failures include source locations when available.\n" \
           "Use --validate to check syntax only, without reading stdin; unknown functions remain valid.\n" \
           "Validate saved queries with --validate --query-file PATH; --file is unavailable during validation.\n" \
           "The two-argument form --validate EXPRESSION always treats EXPRESSION as query text.\n" \
           "Validation exits with status 0 for valid syntax, 1 for query failures, and 2 for usage failures.".freeze

    # @param argv [Array<String>] command-line arguments
    # @param stdin [IO, StringIO] source JSON stream
    # @param stdout [IO, StringIO] result stream
    # @param stderr [IO, StringIO] diagnostic stream
    # @return [Integer] zero on success, one on input failure, two on usage failure
    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      return validation(argv, stderr) if argv.first == "--validate" && argv.length == 2
      return information(argv, stdout) if [%w[--help], %w[-h], %w[--version]].include?(argv)

      expression, path, query_path, validate, pretty, raw_output = parse_arguments(argv)
      expression = read_query(expression, query_path)
      return validation(["--validate", expression], stderr) if validate

      execute(expression, read_document(path, stdin), stdout, pretty, raw_output)
    rescue OptionParser::ParseError
      stderr.puts(USAGE)
      2
    rescue JSON::ParserError, Errors::Error, IOError, SystemCallError => e
      stderr.puts(FailureDiagnostic.format(e, expression))
      1
    end

    # @api private
    def self.parse_arguments(argv)
      return [argv.fetch(0), nil, nil, false, false, false] if argv.one? && !argv.fetch(0).start_with?("-")

      paths = {} # : Hash[String, String]
      arguments = argument_parser(paths).permute(argv)
      check_sources(arguments, paths)

      [arguments.first, paths["file"], paths["query-file"],
       paths.key?("validate"), paths.key?("pretty"), paths.key?("raw-output")]
    end

    # @api private
    def self.check_sources(arguments, paths)
      sources = arguments.length + (paths.key?("query-file") ? 1 : 0)
      raise OptionParser::InvalidArgument, "expected one query source" unless sources == 1

      modes = paths.keys & %w[validate pretty raw-output]
      raise OptionParser::InvalidArgument, "conflicting modes" if modes.length > 1
      return unless paths.key?("validate")
      return if paths.key?("query-file") && !paths.key?("file")

      raise OptionParser::InvalidArgument, "validation requires a query file"
    end

    # @api private
    def self.argument_parser(paths)
      ArgumentParser.new do |options|
        options.on("-h", "--help", "--version", "--*-completion-bash", "--*-completion-zsh") do
          raise OptionParser::InvalidOption, "unsupported option combination"
        end
        %w[file query-file].each do |name|
          options.on("--#{name} PATH") do |value|
            raise OptionParser::InvalidOption, "--#{name} repeated" if paths.key?(name)

            paths[name] = value
          end
        end
        %w[validate pretty raw-output].each do |name|
          options.on("--#{name}") do
            raise OptionParser::InvalidOption, "--#{name} repeated" if paths.key?(name)

            paths[name] = ""
          end
        end
      end
    end

    # @api private
    def self.read_query(expression, path)
      return expression || "" unless path

      File.open(path, "rb:UTF-8:-", &:read)
    end

    # @api private
    def self.read_document(path, stdin)
      return JSON.parse(stdin.read.to_s) unless path

      File.open(path, "r:UTF-8") { |file| JSON.parse(file.read) }
    end

    # @api private
    def self.execute(expression, data, stdout, pretty, raw_output)
      result = JMESPath.search(expression, data)
      output = if raw_output && result.is_a?(String)
                 "#{result}\n"
               else
                 pretty ? JSON.pretty_generate(result) : JSON.generate(result)
               end
      stdout.puts(output)
      0
    end

    # @api private
    def self.validation(argv, errors)
      diagnostic = JMESPath.validate(argv.fetch(1)).first
      return 0 unless diagnostic

      errors.puts(Diagnostic.format(diagnostic))
      1
    end

    # @api private
    def self.information(argv, output)
      output.puts(argv == ["--version"] ? "jmespath-ruby #{VERSION}" : HELP)
      0
    end
  end
end
