# frozen_string_literal: true

require_relative "../jmespath"
require_relative "cli/failure_diagnostic"

module JMESPath
  # Runs a query against standard input or validates query syntax alone.
  module CLI
    USAGE = "Usage: jmespath EXPRESSION < document.json\n       jmespath --validate EXPRESSION"
    HELP = "#{USAGE}\n" \
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

      unless argv.length == 1
        stderr.puts(USAGE)
        return 2
      end
      query(argv.fetch(0), stdin, stdout)
    rescue JSON::ParserError, Errors::Error, IOError, SystemCallError => e
      stderr.puts(FailureDiagnostic.format(e, argv.first))
      1
    end

    # @api private
    def self.query(expression, input, output)
      data = JSON.parse(input.read.to_s)
      output.puts(JSON.generate(JMESPath.search(expression, data)))
      0
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
