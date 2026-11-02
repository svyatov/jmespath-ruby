# frozen_string_literal: true

require_relative "../jmespath"
require_relative "cli/failure_diagnostic"
require_relative "cli/arguments"

module JMESPath
  # Executes document or JSON Lines queries, or validates query syntax.
  module CLI
    USAGE = "Usage: jmespath [--pretty | --raw-output | --json-lines] [--file PATH] " \
            "(EXPRESSION | --query-file PATH)\n       " \
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
           "Use --json-lines for one JSON record per physical input line and one compact result per record.\n" \
           "JSON Lines compiles once before input; empty input succeeds with a valid query.\n" \
           "Blank records are invalid; failures report the input line, retain earlier output, and exit 1.\n" \
           "Memory follows the current record and result; output uses normal buffering.\n" \
           "The --json-lines flag cannot be repeated or combined with --pretty, --raw-output, or --validate.\n" \
           "Function arguments and expression-reference results are validated; failures exit with status 1.\n" \
           "Unknown functions suggest similar registered names.\n" \
           "Query failures include source locations when available.\n" \
           "Use --validate to check syntax only, without reading stdin; unknown functions remain valid.\n" \
           "Validate saved queries with --validate --query-file PATH; --file is unavailable during validation.\n" \
           "The two-argument form --validate EXPRESSION always treats EXPRESSION as query text.\n" \
           "Validation exits with status 0 for valid syntax, 1 for query failures, and 2 for usage failures.".freeze

    # @param argv [Array<String>] command-line arguments
    # @param stdin [IO, StringIO] source stream: read for documents, gets for JSON Lines
    # @param stdout [IO, StringIO] result stream
    # @param stderr [IO, StringIO] diagnostic stream
    # @return [Integer] zero on success, one on input failure, two on usage failure
    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      return validation(argv, stderr) if literal_validation?(argv)
      return information(argv, stdout) if [%w[--help], %w[-h], %w[--version]].include?(argv)

      expression, path, query_path, validate, pretty, raw_output, json_lines = parse_arguments(argv)
      expression = read_query(expression, query_path)
      return validation(["--validate", expression], stderr) if validate
      if json_lines
        # @type var stdin: _LineReader
        return execute_lines(expression, path, stdin, stdout, stderr)
      end

      # @type var stdin: _Reader
      execute(expression, read_document(path, stdin), stdout, pretty, raw_output)
    rescue OptionParser::ParseError
      stderr.puts(USAGE)
      2
    rescue JSON::ParserError, Errors::Error, IOError, SystemCallError => e
      stderr.puts(FailureDiagnostic.format(e, expression))
      1
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
    def self.execute_lines(expression, path, stdin, stdout, stderr)
      compiled = JMESPath.compile(expression)
      return process_lines(compiled, expression, stdin, stdout, stderr) unless path

      File.open(path, "r:UTF-8") { |file| process_lines(compiled, expression, file, stdout, stderr) }
    end

    # @api private
    def self.process_lines(compiled, expression, input, output, errors)
      line_number = 0
      loop do
        line_number += 1
        line = input.gets
        break unless line

        line = line.dup.force_encoding(Encoding::UTF_8)
        raise JSON::ParserError, "Invalid UTF-8 input" unless line.valid_encoding?

        output.puts(JSON.generate(compiled.search(JSON.parse(line))))
      end
      0
    rescue JSON::ParserError, JSON::GeneratorError, Errors::Error, IOError, SystemCallError => e
      errors.puts("Input line #{line_number}:")
      errors.puts(FailureDiagnostic.format(e, expression))
      1
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
