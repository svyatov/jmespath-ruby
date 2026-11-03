# frozen_string_literal: true

require_relative "inspection_report"

module JMESPath
  module CLI
    # @api private
    module InteractiveCommands
      TRACE_LIMIT = 1000

      def self.call(line, data:)
        parts = line.sub(/\A[ \t]+/, "").split(/[ \t]+/, 2)
        query = parts.fetch(1, "")
        execute(parts.fetch(0), query, line, data)
      rescue JSON::NestingError
        ["Invalid JSON result", nil]
      rescue Errors::Error, JSON::GeneratorError => e
        [FailureDiagnostic.format(e, query), nil]
      end

      def self.execute(name, query, line, data)
        case name
        when ":functions" then [functions(query), nil]
        when ":explain" then [explain(query), nil]
        when ":trace" then trace(query, data)
        else
          command = line.sub(/\A[ \t]+/, "").reverse.sub(/\A[ \t]+/, "").reverse
          raise Errors::Error, "Unknown command: #{command}"
        end
      end

      def self.functions(query)
        raise Errors::Error, ":functions does not accept arguments" unless query.empty?

        FunctionListing.render(Functions.default)
      end

      def self.explain(query)
        InspectionReport.explain(compile(query, ":explain").explain)
      end

      def self.compile(query, command)
        raise Errors::Error, "#{command} requires a query" if query.empty?

        JMESPath.compile(query)
      end

      def self.trace(query, data)
        expression = compile(query, ":trace")
        report = expression.trace(data, limit: TRACE_LIMIT)
        result = JSON.generate(report[:value])
        [InspectionReport.trace(expression.explain, report, limit: TRACE_LIMIT), result]
      end

      private_class_method :execute, :functions, :explain, :compile, :trace
    end
  end
end
