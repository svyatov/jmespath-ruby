# frozen_string_literal: true

require "jmespath/cli"
require "reline"
require_relative "../../lib/jmespath/cli/interactive_key_stroke"

RSpec.describe "Interactive UTF-8 key sequences" do
  def matcher
    JMESPath::CLI::InteractiveKeyStroke.new(Reline::Config.new, Encoding::UTF_8)
  end

  def payload_matcher(binding, command)
    config = Reline::Config.new
    config.add_default_key_binding(binding.bytes, command)
    JMESPath::CLI::InteractiveKeyStroke.new(config, Encoding::UTF_8)
  end

  it "preserves ordinary keys and unconsumed input" do
    keys, rest = matcher.expand("name".bytes)
    expect(keys.map { |key| [key.char, key.method_symbol] }).to eq([["n", :ed_insert]])
    expect(rest).to eq("ame".bytes)
  end

  [["\e[200~", :bracketed_paste_start, "é\nflag\e[201~", "é\nflag", :insert_multiline_text],
   ["\e[200~", :bracketed_paste_start, "\e[201~", "", :insert_multiline_text],
   ["\e[200~", :bracketed_paste_start, "name", "name", :insert_multiline_text],
   ["\x11", :quoted_insert, "é", "é", :insert_raw_char],
   ["\x11", :ed_quoted_insert, "", "", :insert_raw_char]].each do |binding, command, input, text, operation|
    it "validates and expands #{command} payload #{input.inspect}" do
      allow(Reline::IOGate).to receive(:getc).with(Float::INFINITY).and_return(*input.bytes, nil)
      keys, rest = payload_matcher(binding, command).expand(binding.bytes)
      expect(rest).to eq([])
      expect(keys.map { |key| [key.char, key.method_symbol] }).to eq([[text, operation]])
    end
  end

  [["\e[200~", :bracketed_paste_start, "\xFF\e[201~"],
   ["\x11", :quoted_insert, "\xFF"],
   ["\x11", :quoted_insert, "\xE2\r"]].each do |binding, command, input|
    it "rejects invalid #{command} payload #{input.b.inspect}" do
      allow(Reline::IOGate).to receive(:getc).with(Float::INFINITY).and_return(*input.bytes, nil)
      expect { payload_matcher(binding, command).expand(binding.bytes) }
        .to raise_error(JMESPath::CLI::InteractiveKeyStroke::InvalidInput)
    end
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
