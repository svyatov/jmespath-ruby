# frozen_string_literal: true

module JMESPath
  class Functions
    # @api private
    module Suggestions
      class << self
        def for(name, names)
          names.filter_map { |candidate| ranked(name, candidate) }.sort.first(3).map(&:last)
        end

        private

        def ranked(name, candidate)
          threshold = [name.length, candidate.length].max <= 4 ? 1 : 2
          return if (name.length - candidate.length).abs > threshold

          score = distance(name, candidate)
          [score, candidate] if score <= threshold
        end

        def distance(left, right)
          left = left.chars
          right = right.chars
          previous = (0..right.length).to_a
          older = previous
          left.each_index do |index|
            current = row(left, right, index, previous, older)
            older = previous
            previous = current
          end
          previous.fetch(right.length)
        end

        def row(left, right, index, previous, older)
          current = [index + 1]
          right.each_index do |column|
            score = [previous.fetch(column + 1) + 1, current.fetch(column) + 1,
                     substitution(left, right, index, column, previous)]
            score << (older.fetch(column - 1) + 1) if swap?(left, right, index, column)
            current << score.min
          end
          current
        end

        def substitution(left, right, index, column, previous)
          previous.fetch(column) + (left[index] == right[column] ? 0 : 1)
        end

        def swap?(left, right, index, column)
          index.positive? && column.positive? && left[index] == right[column - 1] && left[index - 1] == right[column]
        end
      end
    end
  end
end
