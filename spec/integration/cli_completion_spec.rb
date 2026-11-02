# frozen_string_literal: true

require "shellwords"
require "jmespath/cli"
require_relative "../support/shell_completion"

RSpec.describe "Shell completion" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:options) do
    %w[-h --help --version --functions --file --query-file --validate --pretty --raw-output --json-lines]
  end

  around do |example|
    Dir.mktmpdir("jmespath-completion") do |directory|
      Dir.chdir(directory) { example.run }
    end
  end

  %w[bash zsh].each do |shell|
    context shell do
      before do
        skip "#{shell} is unavailable" unless system(shell, "--version", out: File::NULL, err: File::NULL)
        asset = shell == "bash" ? "jmespath.bash" : "_jmespath"
        expect(File).to exist(File.join(root, "completions", asset))
      end

      def complete(line:)
        ShellCompletion.complete(shell: self.class.description, root: root, line: line)
      end

      %w[jmespath jmespath.rb].each do |command|
        it "offers every supported option for #{command} before and after queries" do
          ["#{command} -", "#{command} '@' -", "#{command} --pretty -"].each do |line|
            expect(ShellCompletion.candidates(shell: shell, root: root, line: line).sort).to eq(options.sort)
          end
          expect(complete(line: "#{command} --que")).to eq("#{command} --query-file ")
        end

        it "leaves expressions and delimited text unchanged for #{command}" do
          File.write("document.json", "not read")
          ["#{command} ", "#{command} doc", "#{command} -- --que", "#{command} '@' -- --fi"].each do |line|
            expect(complete(line: line)).to eq(line)
          end
          expect(complete(line: "#{command} --file -- --que")).to eq("#{command} --file -- --query-file ")
        end

        %w[--file --query-file].each do |option|
          [" ", "="].each do |separator|
            it "completes literal paths for #{command} #{option}#{separator}" do
              ["document.json", "query.jmespath", "my document.json", "--document.json",
               "odd'$value.json", "eq=value.json"].each do |name|
                File.write(name, "must not read")
                File.chmod(0, name)
                prefix = Shellwords.escape(name[0, 3])
                result = complete(line: "#{command} #{option}#{separator}#{prefix}")
                words = Shellwords.split(result)
                expected = separator == "=" ? [command, "#{option}=#{name}"] : [command, option, name]
                expect(words).to eq(expected)
                File.unlink(name)
              end
            end
          end
        end

        it "continues through directories and quoted spaces for #{command}" do
          Dir.mkdir("my directory")
          File.write("my directory/document.json", "not read")
          result = complete(line: "#{command} --file my")
          expect(Shellwords.split(result)).to eq([command, "--file", "my directory/"])
          result = complete(line: "#{result}doc")
          expect(Shellwords.split(result)).to eq([command, "--file", "my directory/document.json"])
          result = complete(line: "#{command} --file 'my directory/doc")
          expect(Shellwords.split(result)).to eq([command, "--file", "my directory/document.json"])
        end
      end

      it "does not execute commands from executable names or filename text" do
        File.write("danger$(touch SENTINEL).json", "not read")
        %w[jmespath jmespath.rb].each do |command|
          File.write(command, "#!/bin/sh\ntouch CALLED\nexit 1\n")
          File.chmod(0o755, command)
        end
        original = ENV.fetch("PATH")
        ENV["PATH"] = "#{Dir.pwd}:#{original}"
        result = complete(line: "jmespath --file dan")
        expect(Shellwords.split(result)).to eq(["jmespath", "--file", "danger$(touch SENTINEL).json"])
        expect(File).not_to exist("CALLED")
        expect(File).not_to exist("SENTINEL")
      ensure
        ENV["PATH"] = original if original
      end

      it "completes an empty path prefix without extending a positional expression" do
        File.write("only.json", "not read")
        expect(Shellwords.split(complete(line: "jmespath --file "))).to eq(%w[jmespath --file only.json])
      end

      it "lists named pipes without opening them" do
        File.mkfifo("query.jmespath")
        expect(Shellwords.split(complete(line: "jmespath --query-file que")))
          .to eq(%w[jmespath --query-file query.jmespath])
      end
    end
  end

  it "keeps the expected option surface aligned with the parser" do
    parser = JMESPath::CLI.argument_parser({})
    switches = parser.top.list.flat_map { |switch| switch.short + switch.long }
    expect(switches.reject { |name| name.include?("*") }.sort).to eq(options.sort)
  end
end
