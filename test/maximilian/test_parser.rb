# frozen_string_literal: true

require_relative "../test_helper"

# --- Tests for parse_tool_call -----------------------------------------------

class TestParseToolCall < Minitest::Test
  include Maximilian::Parser

  # PWD variants
  def test_parse_pwd_exact
    result = parse_tool_call("PWD:")
    assert_equal ["PWD", {}], result
  end

  def test_parse_pwd_without_colon
    result = parse_tool_call("PWD")
    assert_equal ["PWD", {}], result
  end

  def test_parse_pwd_with_trailing_space_stripped
    # .strip removes trailing space, so "PWD: " -> "PWD:" which matches
    result = parse_tool_call("PWD: ")
    assert_equal ["PWD", {}], result
  end

  # LISTFILES variants
  def test_parse_listfiles_no_pattern
    result = parse_tool_call("LISTFILES:")
    assert_equal ["LISTFILES", { pattern: "*" }], result
  end

  def test_parse_listfiles_with_pattern
    result = parse_tool_call("LISTFILES: *.rb")
    assert_equal ["LISTFILES", { pattern: "*.rb" }], result
  end

  def test_parse_listfiles_with_tab
    result = parse_tool_call("LISTFILES:\t*.md")
    assert_equal ["LISTFILES", { pattern: "*.md" }], result
  end

  def test_parse_listfiles_empty_pattern_defaults_to_star
    result = parse_tool_call("LISTFILES:")
    assert_equal ["LISTFILES", { pattern: "*" }], result
  end

  def test_parse_listfiles_pattern_with_spaces
    result = parse_tool_call("LISTFILES: *.rb *.md")
    assert_equal ["LISTFILES", { pattern: "*.rb *.md" }], result
  end

  # READFILE variants
  def test_parse_readfile_simple
    result = parse_tool_call("READFILE: config.rb")
    assert_equal ["READFILE", { path: "config.rb" }], result
  end

  def test_parse_readfile_with_spaces
    result = parse_tool_call("READFILE:   /usr/local/bin/script.sh")
    assert_equal ["READFILE", { path: "/usr/local/bin/script.sh" }], result
  end

  def test_parse_readfile_relative_path
    result = parse_tool_call("READFILE: ./src/main.rb")
    assert_equal ["READFILE", { path: "./src/main.rb" }], result
  end

  # RUNCOMMAND variants
  def test_parse_runcommand_simple
    result = parse_tool_call("RUNCOMMAND: ls -la")
    assert_equal ["RUNCOMMAND", { command: "ls -la" }], result
  end

  def test_parse_runcommand_complex
    result = parse_tool_call("RUNCOMMAND: find . -name '*.rb' -exec rm {} \\;")
    assert_equal ["RUNCOMMAND", { command: "find . -name '*.rb' -exec rm {} \\;" }], result
  end

  def test_parse_runcommand_with_tabs
    result = parse_tool_call("RUNCOMMAND:\tgit status")
    assert_equal ["RUNCOMMAND", { command: "git status" }], result
  end

  # WRITEFILE variants
  def test_parse_writefile_basic
    text = "WRITEFILE: /tmp/test.txt\nhello world"
    result = parse_tool_call(text)
    assert_equal ["WRITEFILE", { path: "/tmp/test.txt", content: "hello world\n" }], result
  end

  def test_parse_writefile_multiline
    text = "WRITEFILE: /tmp/test.rb\nputs 'a'\nputs 'b'\n"
    result = parse_tool_call(text)
    assert_equal ["WRITEFILE", { path: "/tmp/test.rb", content: "puts 'a'\nputs 'b'\n" }], result
  end

  def test_parse_writefile_with_spaces_after_colon
    text = "WRITEFILE:   config.yml\nkey: value"
    result = parse_tool_call(text)
    assert_equal ["WRITEFILE", { path: "config.yml", content: "key: value\n" }], result
  end

  def test_parse_writefile_no_content_line_does_not_match
    # After .strip, "WRITEFILE: /tmp/empty.txt" has no newline after path,
    # so the WRITEFILE pattern (which requires \n after path) won't match.
    result = parse_tool_call("WRITEFILE: /tmp/empty.txt")
    assert_nil result
  end

  def test_parse_writefile_no_double_newline
    # Content ending in \n should not get an extra \n appended.
    text = "WRITEFILE: /tmp/test.txt\nhello\n"
    result = parse_tool_call(text)
    assert_equal ["WRITEFILE", { path: "/tmp/test.txt", content: "hello\n" }], result
  end

  # No tool call (nil cases)
  def test_no_tool_call_plain_text
    result = parse_tool_call("Hello, how can I help you?")
    assert_nil result
  end

  def test_no_tool_call_empty_string
    result = parse_tool_call("")
    assert_nil result
  end

  def test_no_tool_call_nil_input
    result = parse_tool_call(nil)
    assert_nil result
  end

  def test_no_tool_call_tool_call_not_last_line
    # PWD is in the middle, text follows
    result = parse_tool_call("PWD:\nsome extra text after")
    assert_nil result
  end

  def test_no_tool_call_tool_call_before_other_text
    result = parse_tool_call("Let me check the directory\nPWD:")
    # This should match because PWD is the last line
    assert_equal ["PWD", {}], result
  end

  def test_no_tool_call_code_block_not_protocol
    result = parse_tool_call("Here's the code:\n```ruby\nputs 'hello'\n```")
    assert_nil result
  end

  def test_no_tool_call_partial_match
    # "READFILE" without colon should not match
    result = parse_tool_call("READFILE")
    assert_nil result
  end

  def test_no_tool_call_runcommand_empty
    # RUNCOMMAND with empty command after stripping
    result = parse_tool_call("RUNCOMMAND:")
    assert_nil result
  end

  def test_no_tool_call_listfiles_vs_readfile
    # Make sure LISTFILES doesn't accidentally match READFILE
    result = parse_tool_call("LISTFILES: *.rb")
    assert_equal "LISTFILES", result[0]
    assert_equal "READFILE", parse_tool_call("READFILE: *.rb")[0]
  end

  # Edge cases
  def test_parse_with_leading_whitespace
    result = parse_tool_call("  PWD:")
    assert_equal ["PWD", {}], result
  end

  def test_parse_with_trailing_newline
    result = parse_tool_call("PWD:\n")
    assert_equal ["PWD", {}], result
  end

  # Regression test: $~ temporal coupling
  # A match? call before parse_tool_call should not corrupt the result.
  def test_parse_tool_call_unaffected_by_prior_match
    "some text".match?(/text/) # populates $~
    result = parse_tool_call("PWD:")
    assert_equal ["PWD", {}], result
  end
end
