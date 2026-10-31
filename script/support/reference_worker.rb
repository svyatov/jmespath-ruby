# frozen_string_literal: true

require "json"
require "open3"
require "io/wait"

# Owns an isolated process speaking one JSON request and response per line.
class ReferenceWorker
  def initialize(command)
    @input, @output, error, @wait = Open3.popen3(*command)
    @errors = Thread.new { error.read }
  end

  def request(payload)
    @input.puts(JSON.generate(payload))
    @input.flush
    raise "Reference process timed out" unless @output.wait_readable(10)

    line = @output.gets
    raise "Reference process exited without a response" unless line

    JSON.parse(line)
  end

  def close
    @input.close unless @input.closed?
    @wait.value
    @output.close
    @errors.value
  end
end
