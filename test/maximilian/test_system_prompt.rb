# frozen_string_literal: true

require_relative "../test_helper"

# --- Tests for SYSTEM_PROMPT integrity ----------------------------------------

class TestSystemPrompt < Minitest::Test
  def test_system_prompt_mentions_all_tools
    assert_includes Maximilian::SYSTEM_PROMPT, "PWD"
    assert_includes Maximilian::SYSTEM_PROMPT, "LISTFILES"
    assert_includes Maximilian::SYSTEM_PROMPT, "READFILE"
    assert_includes Maximilian::SYSTEM_PROMPT, "WRITEFILE"
    assert_includes Maximilian::SYSTEM_PROMPT, "RUNCOMMAND"
  end

  def test_system_prompt_mentions_tool_must_be_last
    assert_match(/last thing in your/i, Maximilian::SYSTEM_PROMPT)
  end

  def test_system_prompt_mentions_no_fencing
    assert_match(/fencing/i, Maximilian::SYSTEM_PROMPT)
  end

  def test_agent_name
    assert_equal "maximilian", Maximilian::AGENT_NAME
  end

  def test_system_prompt_not_empty
    refute_empty Maximilian::SYSTEM_PROMPT
  end

  def test_system_prompt_mentions_agent_name
    # Regression: ensure the typo AGFENT_NAME was fixed
    refute_includes Maximilian::SYSTEM_PROMPT, "AGFENT"
    assert_includes Maximilian::SYSTEM_PROMPT, "maximilian"
  end
end

# --- Smoke test: verify the gem loads without side effects -------------------

class TestLoad < Minitest::Test
  def test_gem_loads_without_error
    assert true
  end

  def test_core_module_methods_defined
    assert Maximilian::Parser.respond_to?(:parse_tool_call)
    assert Maximilian::Shell.respond_to?(:run_command)
    assert Maximilian.respond_to?(:start_spinner)
  end

  def test_spinner_frames_present
    assert_equal 4, Maximilian::SPINNER_FRAMES.size
    assert_includes Maximilian::SPINNER_FRAMES, "|"
    assert_includes Maximilian::SPINNER_FRAMES, "/"
    assert_includes Maximilian::SPINNER_FRAMES, "-"
    assert_includes Maximilian::SPINNER_FRAMES, "\\"
  end

  def test_spinner_frames_frozen
    assert Maximilian::SPINNER_FRAMES.frozen?
  end

  def test_system_prompt_constant_present
    assert_kind_of String, Maximilian::SYSTEM_PROMPT
    refute_empty Maximilian::SYSTEM_PROMPT
  end

  def test_agent_class_defined
    assert defined?(Maximilian::Agent)
    assert defined?(Maximilian::ApiError)
  end

  def test_version_defined
    assert_equal "0.1.0", Maximilian::VERSION
  end
end
