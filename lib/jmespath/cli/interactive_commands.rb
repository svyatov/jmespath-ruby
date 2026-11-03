# frozen_string_literal: true

require_relative "inspection_report"

module JMESPath
  module CLI
    # @api private
    module InteractiveCommands
      def self.call(line)
        parts = line.sub(/\A[ \t]+/, "").split(/[ \t]+/, 2)
        query = parts.fetch(1, "")
        execute(parts.fetch(0), query, line)
      rescue Errors::Error => e
        FailureDiagnostic.format(e, query)
      end

      def self.execute(name, query, line)
        case name
        when ":functions" then functions(query)
        when ":explain" then explain(query)
        else
          command = line.gsub(/\A[ \t]+|[ \t]+\z/, "")
          raise Errors::Error, "Unknown command: #{command}"
        end
      end

      def self.functions(query)
        raise Errors::Error, ":functions does not accept arguments" unless query.empty?

        FunctionListing.render(Functions.default)
      end

      def self.explain(query)
        raise Errors::Error, ":explain requires a query" if query.empty?

        InspectionReport.explain(JMESPath.compile(query).explain)
      end

      private_class_method :execute, :functions, :explain
    end
  end
end
