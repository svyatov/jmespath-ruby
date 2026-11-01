# frozen_string_literal: true

require_relative "../jmespath"
require_relative "cli/failure_diagnostic"

module JMESPath
  # Runs one JMESPath query against a JSON document from standard input.
  module CLI
    USAGE = "Usage: jmespath EXPRESSION < document.json"
    HELP = "#{USAGE}\n" \
           "Function arguments and expression-reference results are validated; failures exit with status 1.\n" \
           "Unknown functions suggest similar registered names.\n" \
           "Query failures include source locations when available.".freeze

    # @param argv [Array<String>] command-line arguments
    # @param stdin [IO, StringIO] source JSON stream
    # @param stdout [IO, StringIO] result stream
    # @param stderr [IO, StringIO] diagnostic stream
    # @return [Integer] zero on success, one on input failure, two on usage failure
    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      return information(argv, stdout) if [%w[--help], %w[-h], %w[--version]].include?(argv)

      unless argv.length == 1
        stderr.puts(USAGE)
        return 2
      end
      data = JSON.parse(stdin.read.to_s)
      stdout.puts(JSON.generate(JMESPath.search(argv.fetch(0), data)))
      0
    rescue JSON::ParserError, Errors::Error, IOError, SystemCallError => e
      stderr.puts(FailureDiagnostic.format(e, argv.first))
      1
    end

    # @api private
    def self.information(argv, output)
      output.puts(argv == ["--version"] ? "jmespath-ruby #{VERSION}" : HELP)
      0
    end
  end
end
