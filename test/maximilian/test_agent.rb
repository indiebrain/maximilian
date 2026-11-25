# frozen_string_literal: true

require_relative "../test_helper"

# --- Tests for path sandboxing ------------------------------------------------

class TestSandbox < Minitest::Test
  def agent_in(dir, **opts)
    Maximilian::Agent.new(
      sandbox_dir: File.realpath(File.expand_path(dir)),
      log_io: StringIO.new,
      **opts
    )
  end

  def test_readfile_inside_sandbox
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "secret.txt"), "top secret")
      agent = agent_in(dir)

      content = agent.send(:read_file, "secret.txt")
      assert_equal "top secret", content
    end
  end

  def test_readfile_escape_attempt
    Dir.mktmpdir do |dir|
      agent = agent_in(dir)
      result = agent.send(:read_file, "../../../etc/passwd")
      assert_includes result, "Error"
      assert_includes result, "outside sandbox"
    end
  end

  def test_writefile_escape_attempt
    Dir.mktmpdir do |dir|
      agent = agent_in(dir)
      result = agent.send(:write_file, "../../etc/cron_d/agent_evil", "evil\n")
      assert_includes result, "Error"
      assert_includes result, "outside sandbox"
    end
  end

  def test_writefile_inside_sandbox
    Dir.mktmpdir do |dir|
      agent = agent_in(dir)
      result = agent.send(:write_file, "output.txt", "hello\n")
      assert_includes result, "File written successfully"
      assert_equal "hello\n", File.read(File.join(dir, "output.txt"))
    end
  end

  def test_readfile_symlink_escape
    Dir.mktmpdir do |sandbox|
      Dir.mktmpdir do |outside_dir|
        outside_file = File.join(outside_dir, "outside.txt")
        File.write(outside_file, "escaped content")

        link = File.join(sandbox, "escape_link.txt")
        File.symlink(outside_file, link)

        agent = agent_in(sandbox)
        result = agent.send(:read_file, "escape_link.txt")
        assert_includes result, "Error"
        assert_includes result, "outside sandbox"
      end
    end
  end

  def test_readfile_absolute_path_outside_sandbox
    Dir.mktmpdir do |dir|
      agent = agent_in(dir)
      result = agent.send(:read_file, "/etc/hostname")
      assert_includes result, "Error"
      assert_includes result, "outside sandbox"
    end
  end
end

# --- Tests for history truncation --------------------------------------------

class TestTruncation < Minitest::Test
  def test_truncate_drops_oldest_messages
    Dir.mktmpdir do |dir|
      agent = Maximilian::Agent.new(
        sandbox_dir: File.realpath(File.expand_path(dir)),
        max_history: 3,
        log_io: StringIO.new
      )

      agent.messages << { role: "user", content: "msg1" }
      agent.messages << { role: "assistant", content: "reply1" }
      agent.messages << { role: "user", content: "msg2" }
      agent.messages << { role: "assistant", content: "reply2" }
      agent.messages << { role: "user", content: "msg3" }

      agent.send(:truncate_history)

      assert_equal 4, agent.messages.size
      assert_equal "system", agent.messages[0][:role]
      contents = agent.messages.map { |m| m[:content] }
      refute_includes contents, "msg1"
      refute_includes contents, "reply1"
      assert_includes contents, "msg3"
      assert_includes contents, "reply2"
    end
  end

  def test_truncate_noop_when_within_limit
    Dir.mktmpdir do |dir|
      agent = Maximilian::Agent.new(
        sandbox_dir: File.realpath(File.expand_path(dir)),
        max_history: 40,
        log_io: StringIO.new
      )
      agent.messages << { role: "user", content: "hello" }
      agent.messages << { role: "assistant", content: "hi" }

      before = agent.messages.dup
      agent.send(:truncate_history)
      assert_equal before, agent.messages
    end
  end

  def test_truncate_preserves_system_message
    Dir.mktmpdir do |dir|
      agent = Maximilian::Agent.new(
        sandbox_dir: File.realpath(File.expand_path(dir)),
        max_history: 2,
        log_io: StringIO.new
      )
      agent.messages << { role: "user", content: "a" }
      agent.messages << { role: "user", content: "b" }
      agent.messages << { role: "user", content: "c" }

      agent.send(:truncate_history)

      assert_equal "system", agent.messages[0][:role]
      assert_equal Maximilian::SYSTEM_PROMPT, agent.messages[0][:content]
    end
  end
end

# --- Tests for rollback on API error -----------------------------------------

class TestRollback < Minitest::Test
  def test_rollback_removes_assistant_and_tool_result
    Dir.mktmpdir do |dir|
      agent = Maximilian::Agent.new(
        api_url: "http://localhost:99999/v1/messages",
        sandbox_dir: File.realpath(File.expand_path(dir)),
        log_io: StringIO.new
      )

      assert_equal 1, agent.messages.size

      agent.instance_variable_set(:@assistant_message, "PWD:\n")

      agent.step

      assert_equal 1, agent.messages.size
      assert_equal "system", agent.messages[0][:role]
      assert_nil agent.instance_variable_get(:@assistant_message)
    end
  end
end

# --- Tests for LISTFILES filters . and .. ------------------------------------

class TestListFilesFilter < Minitest::Test
  def test_listfiles_excludes_dot_and_dotdot
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "real.txt"), "x")
      File.write(File.join(dir, ".hidden"), "y")

      agent = Maximilian::Agent.new(
        sandbox_dir: File.realpath(File.expand_path(dir)),
        log_io: StringIO.new
      )
      result = agent.send(:list_files, "*")

      assert_includes result, "real.txt"
      assert_includes result, ".hidden"
      lines = result.split("\n")
      refute_includes lines, "."
      refute_includes lines, ".."
    end
  end
end
