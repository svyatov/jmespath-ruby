# frozen_string_literal: true

require "pty"
require "timeout"
require "tmpdir"

# Drives Readline and ZLE without executing the completed command.
module ShellCompletion
  BASH = <<~'SHELL'
    source "$PROBE_ROOT/completions/jmespath.bash"
    definition=$(declare -f _jmespath_completion)
    eval "${definition/_jmespath_completion/_probe_original}"
    _jmespath_completion() {
      _probe_original
      printf '%s\0' "${COMPREPLY[@]}" > "$PROBE_CANDIDATES"
    }
    _probe_capture() {
      local entry
      entry=$(builtin history 1)
      [[ $entry == *'#'* ]] || return
      printf '%s' "${entry#*#}" > "$PROBE_RESULT"
      printf '__CAPTURED__'
    }
    HISTFILE=/dev/null
    HISTCONTROL=
    HISTIGNORE=
    set -o history
    PROMPT_COMMAND=_probe_capture
    bind '"\C-x\C-g": "\C-a#\C-e\n"'
    PS1='__READY__'
  SHELL
  ZSH = <<~'SHELL'
    fpath=("$PROBE_ROOT/completions" $fpath)
    autoload -Uz compinit
    compinit -D -i
    compadd() {
      local -a probe_matches
      builtin compadd -A probe_matches "$@"
      printf '%s\0' "${probe_matches[@]}" >> "$PROBE_CANDIDATES"
      builtin compadd "$@"
    }
    _probe_capture() {
      print -rn -- "$BUFFER" > "$PROBE_RESULT"
      print -rn -- '__CAPTURED__'
    }
    zle -N _probe_capture
    bindkey '^X^G' _probe_capture
    bindkey '^I' complete-word
    PS1='__READY__'
  SHELL

  def self.complete(**) = probe(**).fetch(0)

  def self.candidates(**) = probe(**).fetch(1)

  def self.probe(shell:, root:, line:)
    Dir.mktmpdir("jmespath-shell") do |home|
      startup = File.join(home, shell == "bash" ? "bashrc" : ".zshrc")
      File.write(startup, shell == "bash" ? BASH : ZSH)
      environment = probe_environment(root, home)
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

  def self.probe_environment(root, home)
    { "HOME" => home, "ZDOTDIR" => home, "TERM" => "dumb", "INPUTRC" => "/dev/null",
      "PROBE_ROOT" => root, "PROBE_RESULT" => File.join(home, "result"),
      "PROBE_CANDIDATES" => File.join(home, "candidates") }
  end

  def self.interact(reader, writer, environment, line)
    Timeout.timeout(10) do
      read_until(reader, "__READY__")
      writer.write("#{line}\t\C-x\C-g")
      read_until(reader, "__CAPTURED__")
    end
    read_result(environment)
  end

  def self.read_until(reader, marker)
    output = +""
    output << reader.readpartial(4096) until output.include?(marker)
  rescue Timeout::Error
    raise "Shell completion timed out: #{output.inspect}"
  end

  def self.read_result(environment)
    result = File.read(environment.fetch("PROBE_RESULT"))
    path = environment.fetch("PROBE_CANDIDATES")
    candidates = File.exist?(path) ? File.binread(path).split("\0").reject(&:empty?).uniq : []
    [result, candidates]
  end
end
