# frozen_string_literal: true

require "jmespath/cli"
require "reline"
require_relative "../../lib/jmespath/cli/interactive_key_stroke"

RSpec.describe "Interactive UTF-8 key sequences" do
  def matcher
    JMESPath::CLI::InteractiveKeyStroke.new(Reline::Config.new, Encoding::UTF_8)
  end

  ["n", "é", "✓", "\e[D", "\r", "\0"].each do |source|
    it "preserves valid key sequence #{source.inspect}" do
      expect(matcher.match_status(source.bytes)).to eq(:matched)
    end
  end

  it "accepts incomplete Unicode prefixes until another byte arrives" do
    expect(matcher.match_status([226])).to eq(:matching_matched)
    expect(matcher.match_status([226, 156])).to eq(:matching_matched)
  end

  ["\xFF", "\xC0\xAF", "\xED\xA0\x80", "\xF4\x90\x80\x80"].each do |source|
    it "rejects invalid byte sequence #{source.b.inspect}" do
      expect { matcher.match_status(source.bytes) }
        .to raise_error(JMESPath::CLI::InteractiveKeyStroke::InvalidInput)
    end
  end

  [["\xE2\r", true], ["\xE2\n", true], ["\xE2\x04", true], ["\xFF", false]].each do |source, ended|
    it "identifies a consumed line terminator for #{source.b.inspect}" do
      expect { matcher.match_status(source.bytes) }
        .to raise_error(JMESPath::CLI::InteractiveKeyStroke::InvalidInput) { |error|
          expect([error.byte, error.ended?]).to eq([source.bytes.last, ended])
        }
    end
  end
end
