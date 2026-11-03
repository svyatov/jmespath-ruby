# frozen_string_literal: true

require_relative "../jmespath"
require_relative "cli/failure_diagnostic"
require_relative "cli/arguments"
require_relative "cli/function_listing"
require_relative "cli/interactive_commands"
require_relative "cli/interactive_editor"
require_relative "cli/interactive_session"
require_relative "cli/help"

module JMESPath
  # Executes queries, validates syntax, or lists built-in functions.
  module CLI
    # @param argv [Array<String>] command-line arguments
    # @param stdin [IO, StringIO] read for documents, gets for JSON Lines or interactive queries; optional tty?
    # @param stdout [IO, StringIO] result stream
    # @param stderr [IO, StringIO] diagnostic stream
    # @return [Integer] zero on success, one on input failure, two on usage failure
    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      return validation(argv, stderr) if literal_validation?(argv)
      return help(argv, stdout) if %w[--help -h].include?(argv.first)
      return information(argv, stdout) if [%w[--version], %w[--functions]].include?(argv)

      query(argv, stdin, stdout, stderr)
    rescue OptionParser::ParseError
      stderr.puts("#{USAGE}\nUse jmespath --help for options and topic help.")
      2
    rescue JSON::ParserError, Errors::Error, IOError, SystemCallError => e
      failure(e, nil, stderr)
    end

    # @api private
    def self.query(argv, stdin, stdout, stderr)
      expression, path, query_path, validate, pretty, raw_output, json_lines, interactive = parse_arguments(argv)
      return interactive_session(path, stdin, stdout, stderr) if interactive

      expression = read_query(expression, query_path)
      return validation(["--validate", expression], stderr) if validate
      if json_lines
        # @type var stdin: _LineReader
        return execute_lines(expression, path, stdin, stdout, stderr)
      end

      # @type var stdin: _Reader
      execute(expression, read_document(path, stdin), stdout, pretty, raw_output)
    rescue JSON::ParserError, Errors::Error => e
      failure(e, expression, stderr)
    end

    # @api private
    def self.failure(error, expression, errors)
      errors.puts(FailureDiagnostic.format(error, expression))
      1
    rescue IOError, SystemCallError
      1
    end

    # @api private
    def self.interactive_session(path, input, output, errors)
      # @type var input: _Reader & _LineReader
      data = read_document(path, input)
      InteractiveSession.new(data, input: input, output: output, errors: errors).run
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
    def self.help(argv, output)
      raise OptionParser::InvalidArgument, "expected at most one help topic" if argv.length > 2

      output.puts(Help.render(argv[1]))
      0
    end

    # @api private
    def self.information(argv, output)
      if argv == ["--functions"]
        output.puts(FunctionListing.render(Functions.default))
        return 0
      end

      output.puts("jmespath-ruby #{VERSION}")
      0
    end
  end
end
