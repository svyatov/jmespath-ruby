# frozen_string_literal: true

require "pty"
require "io/console"
require "timeout"
require "rbconfig"

module InteractiveTerminal
  def with_terminal(arguments, environment: {}, expected_status: 0)
    reset_terminal_buffers
    PTY.open do |master, slave|
      original = prepare_terminal(slave)
      output, writer = IO.pipe
      pid = spawn_terminal(arguments, slave, writer, environment)
      writer.close
      status = await_terminal(pid) { yield master, output, pid }
      pid = nil
      verify_terminal(slave, original, status, expected_status)
    rescue Timeout::Error
      raise "Terminal timeout: #{@terminal_transcript.inspect}"
    ensure
      stop_terminal(pid) if pid
      close_terminal_streams(output, writer)
    end
  end

  def reset_terminal_buffers
    @terminal_buffer = +""
    @terminal_transcript = +""
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

  def verify_terminal(slave, original, status, expected_status)
    expect(status.exitstatus).to eq(expected_status)
    expect(IO.popen(["stty", "-g"], "r", in: slave, &:read)).to eq(original)
  end

  def spawn_terminal(arguments, slave, writer, environment)
    Process.spawn({ "TERM" => "xterm-256color" }.merge(environment), RbConfig.ruby, *arguments,
                  in: slave, out: writer, err: slave)
  end

  def stop_terminal(pid)
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  def terminal_until(master, text)
    until @terminal_buffer.include?(text)
      chunk = master.readpartial(4096)
      @terminal_transcript << chunk
      @terminal_buffer << chunk
      if @terminal_buffer.include?("\e[6n")
        master.write("\e[1;1R")
        @terminal_buffer.gsub!("\e[6n", "")
      end
    end
    @terminal_buffer.slice!(0, @terminal_buffer.index(text) + text.bytesize)
  end
end
