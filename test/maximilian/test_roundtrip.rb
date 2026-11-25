# frozen_string_literal: true

require_relative "../test_helper"

# --- Tests for parse_tool_call round-trip with run_command results -----------

class TestRoundTrip < Minitest::Test
  include Maximilian::Parser
  include Maximilian::Shell

  def test_pwd_roundtrip
    tool_name, params = parse_tool_call("PWD:")
    assert_equal "PWD", tool_name
    assert_equal({}, params)
  end

  def test_listfiles_roundtrip_with_globs
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.rb"), "puts 1")
      File.write(File.join(dir, "test.md"), "# test")

      result = Dir.glob(File.join(dir, "*.rb"), File::FNM_PATHNAME | File::FNM_DOTMATCH)
                  .first(500)
                  .reject { |f| [".", ".."].include?(File.basename(f)) }
                  .join("\n")
      assert_includes result, "test.rb"
      refute_includes result, "test.md"
    end
  end

  def test_readfile_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, "hello.txt")
      File.write(path, "hello content")

      tool_name, params = parse_tool_call("READFILE: #{path}")
      assert_equal "READFILE", tool_name
      assert_equal path, params[:path]
      assert_equal "hello content", File.read(path)
    end
  end

  def test_writefile_roundtrip
    Dir.mktmpdir do |dir|
      path = File.join(dir, "output.txt")

      tool_name, params = parse_tool_call("WRITEFILE: #{path}\nline1\nline2")
      assert_equal "WRITEFILE", tool_name
      assert_equal path, params[:path]
      assert_equal "line1\nline2\n", params[:content]

      File.write(path, params[:content])
      assert_equal "line1\nline2\n", File.read(path)
    end
  end

  def test_runcommand_roundtrip
    Dir.mktmpdir do |dir|
      cmd = "echo 'result' > #{dir}/out.txt && cat #{dir}/out.txt"
      tool_name, params = parse_tool_call("RUNCOMMAND: #{cmd}")
      assert_equal "RUNCOMMAND", tool_name
      assert_equal cmd, params[:command]

      output, status = run_command(cmd, 10)
      assert_equal "result\n", output
      assert_equal "0", status
    end
  end
end
