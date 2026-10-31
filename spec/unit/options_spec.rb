# frozen_string_literal: true

RSpec.describe "Search option validation" do
  [{ unknown: true }, { max_depth: 0 }, { max_depth: 129 }, { max_depth: 1.5 },
   { cache_expressions: 1 }, { disable_visit_errors: nil }, { functions: Object.new }].each do |options|
    it("rejects #{options.inspect}") { expect { JMESPath.search("@", {}, **options) }.to raise_error(ArgumentError) }
  end
end
