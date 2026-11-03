# frozen_string_literal: true

module JMESPath
  module CLI
    # @api private
    class InspectionReport
      def self.explain(explanation)
        new(explanation).explain
      end

      def initialize(explanation)
        @source = explanation[:source]
        @root = explanation[:root]
      end

      def explain
        tree(@root).join("\n")
      end

      private

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
