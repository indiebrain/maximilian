# frozen_string_literal: true

require "open3"

module Maximilian
  # Runs shell commands with a timeout.
  module Shell
    module_function

    # Run a shell command and return [output, status_string].
    # Stops the command and everything it started after timeout seconds.
    #
    # The status is always a String so callers never see nil:
    #   "0"        - process exited successfully
    #   "42"       - process exit code
    #   "error"    - could not spawn the command (SystemCallError)
    #   "killed..."- killed after the timeout
    def run_command(command, timeout)
      Open3.popen2e(command, pgroup: true) do |stdin, output, wait|
        stdin.close
        reader = Thread.new { output.read }
        unless wait.join(timeout)
          Process.kill("TERM", -wait.pid)
          wait.join
          status_str = "killed (timeout #{timeout}s)"
          return ["#{reader.value}\n(stopped after #{timeout} seconds)\n", status_str]
        end
        [reader.value, wait.value.exitstatus.to_s]
      end
    rescue SystemCallError => e
      ["Error: could not run '#{command}': #{e.message}\n", "error"]
    end
  end
end
