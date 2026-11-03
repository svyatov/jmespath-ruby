# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InspectionReport
      def self.explain(explanation)
        new(explanation).explain
      end

      def self.trace(explanation, report, limit:)
        new(explanation).trace(report, limit: limit)
      end

      def initialize(explanation)
        @source = explanation[:source]
        @root = explanation[:root]
      end

      def explain
        tree(@root).join("\n")
      end

      def trace(report, limit:)
        locations = {} # : Hash[Integer, String]
        index_locations(@root, locations)
        lines = report[:events].map { |event| event_line(event, locations) }
        lines << "Trace: no diagnostic events." if lines.empty?
        lines << "Trace truncated: showing first #{limit} events; evaluation completed." if report[:truncated]
        lines.join("\n")
      end

      private

      def index_locations(node, locations)
        locations[node[:id]] = location(node[:source_range])
        node[:children].each { |child| index_locations(child[:node], locations) }
      end

      def event_line(event, locations)
        [event[:type], "##{event[:operation_id]}", locations.fetch(event[:operation_id]),
         details(event[:details]), context(event[:context])].reject(&:empty?).join(" ")
      end

      def context(frames)
        return "" if frames.empty?

        entries = frames.map { |frame| "##{frame[:operation_id]} index=#{frame[:index]}" }
        "context=[#{entries.join(', ')}]"
      end

      def tree(node, indent = "", role = nil)
        line = indent + [role, label(node)].compact.join(": ")
        [line] + node[:children].flat_map { |child| tree(child[:node], "#{indent}  ", child[:role]) }
      end

      def label(node)
        ["##{node[:id]}", node[:operation], location(node[:source_range]), details(node[:details])]
          .reject(&:empty?).join(" ")
      end

      def location(range)
        return "location unavailable" unless range

        prefix = @source.byteslice(0, range[0]).to_s
        line = prefix.count("\n") + 1
        column = prefix.rpartition("\n").last.length + 1
        "line #{line}, column #{column} (bytes #{range[0]}...#{range[1]})"
      end

      def details(values)
        values.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")
      end
    end
  end
end
