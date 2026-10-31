# frozen_string_literal: true

require "yard"
require_relative "../../script/support/doc_examples"

YARD.parse(Dir[File.expand_path("../../lib/**/*.rb", __dir__)])
examples = DocExamples.markdown(File.expand_path("../..", __dir__)) + DocExamples.yard

RSpec.describe "Executable documentation" do
  examples.each do |example|
    it(example.fetch(:label)) { DocExamples.verify(example) }
  end
end
