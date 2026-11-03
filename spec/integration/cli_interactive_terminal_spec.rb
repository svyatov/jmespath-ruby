# frozen_string_literal: true

require "tmpdir"
require "json"
require_relative "../support/interactive_terminal"

RSpec.describe "Interactive terminal editing" do
  include InteractiveTerminal

  around do |example|
    Dir.mktmpdir("jmespath-terminal") do |directory|
      @path = File.join(directory, "document.json")
      File.write(@path, JSON.generate(name: "café", flag: false))
      example.run
    end
  end

  def arguments(name)
    [File.expand_path("../../exe/#{name}", __dir__), "--interactive", "--file", @path]
  end

  %w[jmespath jmespath.rb].each do |name|
    it "edits queries with JSON-only stdout through #{name}" do
      with_terminal(arguments(name)) do |master, output, _pid|
        terminal_until(master, "jmespath> ")
        master.write("nme\e[D\e[Da\r")
        terminal_until(master, "jmespath> ")
        expect(output.gets).to eq("\"café\"\n")
        master.write(":quit\r")
      end
    end

    it "cancels partial edits and accepts EOF through #{name}" do
      with_terminal(arguments(name)) do |master, output, pid|
        terminal_until(master, "jmespath> ")
        master.write("partial")
        terminal_until(master, "partial")
        Process.kill("INT", pid)
        terminal_until(master, "jmespath> ")
        master.write("name\r")
        terminal_until(master, "jmespath> ")
        expect(output.gets).to eq("\"café\"\n")
        master.write("\x04")
      end
    end
  end
end
