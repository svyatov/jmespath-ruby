# frozen_string_literal: true

require_relative "../jmespath"
require_relative "cli/failure_diagnostic"
require "optparse"

module JMESPath
  # Queries a JSON document from stdin or a UTF-8 file, or validates query syntax alone.
  module CLI
    USAGE = "Usage: jmespath [--file PATH] EXPRESSION\n       jmespath --validate EXPRESSION"
    HELP = "#{USAGE}\n" \
           "Read one UTF-8 JSON document from --file PATH, or stdin when omitted.\n" \
           "Options may precede or follow EXPRESSION; -- ends option parsing.\n" \
           "Quote spaces: --file 'my document.json'. Use --file=--document.json for option-like names.\n" \
           "Paths are literal: --file - reads the file named -.\n" \
           "Function arguments and expression-reference results are validated; failures exit with status 1.\n" \
           "Unknown functions suggest similar registered names.\n" \
           "Query failures include source locations when available.\n" \
           "Use --validate to check syntax only, without reading stdin; unknown functions remain valid.\n" \
           "Validation exits with status 0 for valid syntax, 1 for query failures, and 2 for usage failures.".freeze

    # @param argv [Array<String>] command-line arguments
    # @param stdin [IO, StringIO] source JSON stream
    # @param stdout [IO, StringIO] result stream
    # @param stderr [IO, StringIO] diagnostic stream
    # @return [Integer] zero on success, one on input failure, two on usage failure
    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      return validation(argv, stderr) if argv.first == "--validate"
      return information(argv, stdout) if [%w[--help], %w[-h], %w[--version]].include?(argv)

      expression, path = parse_arguments(argv)
      data = read_document(path, stdin)
      stdout.puts(JSON.generate(JMESPath.search(expression, data)))
      0
    rescue OptionParser::ParseError
      stderr.puts(USAGE)
      2
    rescue JSON::ParserError, Errors::Error, IOError, SystemCallError => e
      stderr.puts(FailureDiagnostic.format(e, expression))
      1
    end

    # @api private
    def self.parse_arguments(argv)
      return [argv.fetch(0), nil] if argv.one? && !argv.fetch(0).start_with?("-")

      path = nil
      arguments = OptionParser.new do |options|
        options.require_exact = true
        options.on("-h", "--help", "--version", "--*-completion-bash", "--*-completion-zsh") do
          raise OptionParser::InvalidOption, "unsupported option combination"
        end
        options.on("--file PATH") do |value|
          raise OptionParser::InvalidOption, "--file repeated" if path

          path = value
        end
      end.permute(argv)
      raise OptionParser::InvalidArgument, "expected one expression" unless arguments.length == 1

      [arguments.fetch(0), path]
    end

    # @api private
    def self.read_document(path, stdin)
      return JSON.parse(stdin.read.to_s) unless path

      File.open(path, "r:UTF-8") { |file| JSON.parse(file.read) }
    end

    # @api private
    def self.validation(argv, errors)
      unless argv.length == 2
        errors.puts(USAGE)
        return 2
      end
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
