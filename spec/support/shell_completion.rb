# frozen_string_literal: true

require "pty"
require "timeout"
require "tmpdir"
require_relative "shell_completion_setup"

# Drives Readline and ZLE, with capture functions for accepted arguments.
module ShellCompletion
  def self.complete(**) = probe(**).fetch(0)

  def self.candidates(**) = probe(**, candidates_only: true).fetch(1)

  def self.arguments(**) = probe(**, accept_arguments: true).fetch(0).split("\0")

  def self.probe(shell:, root:, line:, home_directory: nil, **options)
    Dir.mktmpdir("jmespath-shell") do |home|
      startup = File.join(home, shell == "bash" ? "bashrc" : ".zshrc")
      File.write(startup, shell == "bash" ? BASH : ZSH)
      environment = probe_environment(root, home, home_directory, options)
      run(shell, startup, environment, "#{line}#{"\C-b" * options.fetch(:cursor_back, 0)}")
    end
  end

  def self.run(shell, startup, environment, line)
    arguments = shell == "bash" ? ["--noprofile", "--rcfile", startup, "-i"] : ["-d", "-i"]
    result = nil
    PTY.spawn(environment, shell, *arguments) do |reader, writer, pid|
      result = interact(reader, writer, environment, line)
    ensure
      reader.close unless reader.closed?
      writer.close unless writer.closed?
      stop(pid)
    end
    result
  end

  def self.stop(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    nil
  ensure
    begin
      Timeout.timeout(5) { Process.wait(pid) }
    rescue Errno::ECHILD
      nil
    end
  end

  def self.probe_environment(root, home, home_directory, options)
    { "HOME" => home_directory || home, "ZDOTDIR" => home, "TERM" => "dumb", "INPUTRC" => "/dev/null",
      "PROBE_ROOT" => root, "PROBE_RESULT" => File.join(home, "result"),
      "PROBE_CANDIDATES" => File.join(home, "candidates"),
      "PROBE_CANDIDATES_ONLY" => options[:candidates_only] ? "1" : "0",
      "PROBE_ACCEPT_ARGUMENTS" => options[:accept_arguments] ? "1" : "0" }
  end

  def self.interact(reader, writer, environment, line)
    Timeout.timeout(10) do
      read_until(reader, "__READY__")
      writer.write("#{line}\t#{capture_key(environment)}")
      read_until(reader, "__CAPTURED__")
    end
    read_result(environment)
  end

  def self.capture_key(environment)
    return "\n" if environment.fetch("PROBE_ACCEPT_ARGUMENTS") == "1"

    environment.fetch("PROBE_CANDIDATES_ONLY") == "1" ? "" : "\C-x\C-g"
  end

  def self.read_until(reader, marker)
    output = +""
    output << reader.readpartial(4096) until output.include?(marker)
  rescue Timeout::Error
    raise "Shell completion timed out: #{output.inspect}"
  end

  def self.read_result(environment)
    result = environment.fetch("PROBE_CANDIDATES_ONLY") == "1" ? "" : File.read(environment.fetch("PROBE_RESULT"))
    path = environment.fetch("PROBE_CANDIDATES")
    candidates = File.exist?(path) ? File.binread(path).split("\0").reject(&:empty?).uniq : []
    [result, candidates]
  end
end
