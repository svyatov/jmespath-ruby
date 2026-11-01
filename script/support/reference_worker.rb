# frozen_string_literal: true

require "json"
require "open3"
require "io/wait"

# Owns an isolated process speaking one JSON request and response per line.
class ReferenceWorker
  def initialize(command, timeout: 10)
    @timeout = timeout
    @input, @output, error, @wait = Open3.popen3(*command)
    @errors = Thread.new { error.read }
  end

  def request(payload)
    raise "Reference process unavailable" if @closed

    @input.puts(JSON.generate(payload))
    @input.flush
    unless @output.wait_readable(@timeout)
      terminate
      close
      raise "Reference process timed out"
    end

    line = @output.gets
    raise "Reference process exited without a response" unless line

    JSON.parse(line)
  end

  def close
    return @diagnostics if @closed

    @input.close unless @input.closed?
    terminate unless @wait.join(1)
    @output.close
    @diagnostics = @errors.value
    @closed = true
    @diagnostics
  end

  private

  def terminate
    Process.kill("TERM", @wait.pid)
    Process.kill("KILL", @wait.pid) unless @wait.join(1)
    @wait.value
  rescue Errno::ESRCH
    @wait.value
  end
end
