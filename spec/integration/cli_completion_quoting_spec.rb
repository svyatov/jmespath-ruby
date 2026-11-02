# frozen_string_literal: true

require "shellwords"
require_relative "../support/shell_completion"

RSpec.describe "Shell completion quoting and cursor positions" do
  let(:root) { File.expand_path("../..", __dir__) }

  around do |example|
    Dir.mktmpdir("jmespath-quoted-completion") do |directory|
      Dir.chdir(directory) { example.run }
    end
  end

  %w[bash zsh].each do |shell|
    context shell do
      before do
        skip "#{shell} is unavailable" unless system(shell, "--version", out: File::NULL, err: File::NULL)
      end

      %w[jmespath jmespath.rb].each do |command|
        it "recognizes quoted options and delimiters for #{command}" do
          File.write("document.json", "not read")
          ["'", '"'].each do |quote|
            %w[--file --query-file].each do |option|
              [" ", "="].each do |separator|
                line = "#{command} #{quote}#{option}#{quote}#{separator}doc"
                result = ShellCompletion.complete(shell: shell, root: root, line: line)
                expected = separator == " " ? [option, "document.json"] : ["#{option}=document.json"]
                expect(Shellwords.split(result)).to eq([command, *expected])
              end
              line = "#{command} #{quote}#{option}=doc#{quote}"
              result = ShellCompletion.complete(shell: shell, root: root, line: line)
              expect(Shellwords.split(result)).to eq([command, "#{option}=document.json"])
            end
            line = "#{command} #{quote}--#{quote} --que"
            expect(ShellCompletion.complete(shell: shell, root: root, line: line)).to eq(line)
          end
        end

        it "completes ANSI-C quoted filename prefixes for #{command}" do
          File.write("line\nbreak.json", "not read")
          %w[--file --query-file].each do |option|
            [" ", "="].each do |separator|
              ["", "'"].each do |closing_quote|
                line = "#{command} #{option}#{separator}$'line\\nb#{closing_quote}"
                arguments = ShellCompletion.arguments(shell: shell, root: root, line: line)
                expected = separator == " " ? [option, "line\nbreak.json"] : ["#{option}=line\nbreak.json"]
                expect(arguments).to eq(expected)
              end
            end
          end
        end

        it "preserves whole-assignment quote context for #{command}" do
          File.write("odd'name.json", "not read")
          line = "#{command} \"--file=odd'na\""
          expect(ShellCompletion.arguments(shell: shell, root: root, line: line)).to eq(["--file=odd'name.json"])
          Dir.mkdir("~")
          File.write("~/literal.json", "not read")
          line = "#{command} '--file=~/lit'"
          arguments = ShellCompletion.arguments(shell: shell, root: root, line: line)
          expect([["--file=~/literal.json"], ["--file=./~/literal.json"]]).to include(arguments)
        end

        it "completes filename prefixes before the cursor for #{command}", if: shell == "bash" do
          File.write("document.json", "not read")
          %w[--file --query-file].each do |option|
            [" ", "="].each do |separator|
              line = "#{command} #{option}#{separator}doc.json"
              candidates = ShellCompletion.candidates(shell: shell, root: root, line: line, cursor_back: 5)
              expect(candidates).to include("document.json")
            end
          end
        end

        it "uses Bash ANSI-C null termination and literal invalid escapes", if: shell == "bash" do
          File.write("document.json", "not read")
          File.write("docx.json", "not read")
          File.write('a\xqb.json', "not read")
          %w[\0 \c@ \x00].each do |escape|
            line = "#{command} --file $'doc#{escape}x'"
            candidates = ShellCompletion.candidates(shell: shell, root: root, line: line)
            expect(candidates).to include("document.json", "docx.json")
          end
          line = "#{command} --file $'a\\xqb'"
          expect(ShellCompletion.candidates(shell: shell, root: root, line: line)).to include('a\xqb.json')
        end

        next unless shell == "zsh"

        it "expands HOME in double-quoted equals values for #{command}" do
          home = File.join(Dir.pwd, "home")
          Dir.mkdir(home)
          File.write(File.join(home, "document.json"), "not read")
          line = "#{command} --file=\"$HOME/doc"
          arguments = ShellCompletion.arguments(shell: shell, root: root, home_directory: home, line: line)
          expect(arguments).to eq(["--file=#{home}/document.json"])
        end

        it "continues through quoted literal directories for #{command}" do
          Dir.mkdir("~")
          Dir.mkdir("~/directory")
          File.write("~/directory/child.json", "not read")
          line = "#{command} --file=\"~/dir\tchi"
          arguments = ShellCompletion.arguments(shell: shell, root: root, line: line)
          expect(arguments).to eq(["--file=~/directory/child.json"])
          Dir.mkdir("line\ndirectory")
          File.write("line\ndirectory/child.json", "not read")
          line = "#{command} --file $'line\\ndir'\tchi"
          arguments = ShellCompletion.arguments(shell: shell, root: root, line: line)
          expect(arguments).to eq(["--file", "line\ndirectory/child.json"])
        end

        it "preserves quoted literal tilde paths in equals values for #{command}" do
          Dir.mkdir("~")
          File.write("~/literal.json", "not read")
          %w[--file --query-file].each do |option|
            ["'", '"'].each do |quote|
              line = "#{command} #{option}=#{quote}~/lit"
              result = ShellCompletion.complete(shell: shell, root: root, line: line)
              expect(Shellwords.split(result)).to eq([command, "#{option}=~/literal.json"])
            end
          end
        end
      end
    end
  end
end
