# frozen_string_literal: true

require "json"
require "jmespath"

ERRORS = {
  JMESPath::Errors::SyntaxError => "syntax",
  JMESPath::Errors::InvalidTypeError => "invalid-type",
  JMESPath::Errors::InvalidValueError => "invalid-value",
  JMESPath::Errors::InvalidArityError => "invalid-arity",
  JMESPath::Errors::UnknownFunctionError => "unknown-function"
}.freeze

$stdin.each_line do |line|
  request = JSON.parse(line)
  result = begin
    { "value" => JMESPath.search(request.fetch("expression"), request.fetch("given")) }
  rescue StandardError => e
    category = ERRORS.find { |type, _name| e.is_a?(type) }
    category ? { "error" => category.last } : { "crash" => e.class.name, "message" => e.message }
  end
  puts JSON.generate(result)
  $stdout.flush
end
