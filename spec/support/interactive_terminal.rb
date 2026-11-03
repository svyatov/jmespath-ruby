# frozen_string_literal: true

require "pty"
require "io/console"
require "timeout"
require "rbconfig"

module InteractiveTerminal
  def with_terminal(arguments)
    PTY.open do |master, slave|
      original = prepare_terminal(slave)
      output, writer = IO.pipe
      pid = spawn_terminal(arguments, slave, writer)
      writer.close
      status = await_terminal(pid) { yield master, output, pid }
      pid = nil
      verify_terminal(slave, original, status)
    rescue Timeout::Error
      raise "Terminal timeout: #{@terminal_transcript.inspect}"
    ensure
      stop_terminal(pid) if pid
      close_terminal_streams(output, writer)
    end
  end

  def close_terminal_streams(*streams)
    streams.compact.each { |stream| stream.close unless stream.closed? }
  end

  def await_terminal(pid)
    Timeout.timeout(10) do
      yield
      Process.wait2(pid).last
    end
  end

  def prepare_terminal(slave)
    slave.winsize = [24, 100]
    # macOS sets PENDIN after an empty raw block; establish that baseline first.
    slave.raw { nil }
    IO.popen(["stty", "-g"], "r", in: slave, &:read)
  end

  def verify_terminal(slave, original, status)
    expect(status.exitstatus).to eq(0)
    expect(IO.popen(["stty", "-g"], "r", in: slave, &:read)).to eq(original)
  end

  def spawn_terminal(arguments, slave, writer)
    Process.spawn({ "TERM" => "xterm-256color" }, RbConfig.ruby, *arguments,
                  in: slave, out: writer, err: slave)
  end

  def stop_terminal(pid)
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  def terminal_until(master, text)
    @terminal_transcript ||= +""
    buffer = +""
    until buffer.include?(text)
      chunk = master.readpartial(4096)
      @terminal_transcript << chunk
      buffer << chunk
      if buffer.include?("\e[6n")
        master.write("\e[1;1R")
        buffer.gsub!("\e[6n", "")
      end
    end
    buffer
  end
end
