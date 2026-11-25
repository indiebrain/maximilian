# frozen_string_literal: true

require_relative "../test_helper"

# --- Tests for run_command ----------------------------------------------------

class TestRunCommand < Minitest::Test
  include Maximilian::Shell

  def test_run_command_echo
    output, status = run_command("echo hello", 10)
    assert_equal "hello\n", output
    assert_equal "0", status
  end

  def test_run_command_multiline_output
    output, status = run_command("echo line1; echo line2", 10)
    assert_includes output, "line1"
    assert_includes output, "line2"
    assert_equal "0", status
  end

  def test_run_command_nonzero_exit
    _output, status = run_command("exit 42", 10)
    assert_equal "42", status
  end

  def test_run_command_stderr_merged
    output, status = run_command("echo stdout; echo stderr 1>&2", 10)
    assert_includes output, "stdout"
    assert_includes output, "stderr"
    assert_equal "0", status
  end

  def test_run_command_timeout
    output, status = run_command("sleep 30", 1)
    assert_includes output, "stopped after"
    assert_includes status, "killed"
  end

  def test_run_command_pipe
    output, status = run_command("echo 'hello world' | wc -w", 10)
    assert_equal 2, output.to_i
    assert_equal "0", status
  end

  def test_run_command_chained_commands
    Dir.mktmpdir do |dir|
      cmd = "mkdir -p #{dir}/sub && ls #{dir}/sub"
      _output, status = run_command(cmd, 10)
      assert_equal "0", status
    end
  end

  def test_run_command_nonexistent_binary
    output, status = run_command("nonexistent_command_xyz_12345", 10)
    assert_includes output, "Error: could not run"
    assert_equal "error", status
  end
end
