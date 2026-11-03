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

  it "creates no history or configuration files" do
    Dir.mktmpdir("jmespath-terminal-home") do |home|
      environment = { "HOME" => home, "XDG_CONFIG_HOME" => home }
      with_terminal(arguments("jmespath"), environment: environment) do |master, output, _|
        terminal_until(master, "jmespath> ")
        master.write("name\r")
        terminal_until(master, "jmespath> ")
        expect(output.gets).to eq("\"café\"\n")
        master.write(":quit\r")
      end
      expect(Dir.children(home)).to eq([])
    end
  end

  %w[jmespath jmespath.rb].each do |name|
    it "recalls an invalid query for correction through #{name}" do
      with_terminal(arguments(name)) do |master, output, _pid|
        terminal_until(master, "jmespath> ")
        master.write("nam[\r")
        terminal_until(master, "Expected")
        terminal_until(master, "jmespath> ")
        master.write("\e[A\x7fe\r")
        terminal_until(master, "jmespath> ")
        expect(output.gets).to eq("\"café\"\n")
        master.write(":quit\r")
      end
    end

    it "submits pasted physical lines separately through #{name}" do
      with_terminal(arguments(name)) do |master, output, _pid|
        terminal_until(master, "jmespath> ")
        master.write("\e[200~name\nflag\e[201~\r")
        terminal_until(master, "jmespath> ")
        expect(output.gets).to eq("\"café\"\n")
        expect(output.gets).to eq("false\n")
        master.write(":quit\r")
      end
    end

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
