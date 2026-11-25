# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "parser"
require_relative "shell"

# Maximilian — a CLI coding assistant that streams replies from a model API,
# parses tool calls from the reply, executes them (PWD, LISTFILES, READFILE,
# WRITEFILE, RUNCOMMAND), and feeds results back into the conversation.
module Maximilian
  SPINNER_FRAMES = %w[| / - \\].freeze

  # Raised when the API returns an error, before or during a streamed reply.
  class ApiError < StandardError; end

  # ─── Busy spinner ---------------------------------------------------------

  # Returns a lambda that, when called, stops the spinner and clears the line.
  # Call at most once; subsequent calls are no-ops.
  def self.start_spinner(label = "Thinking...")
    running = true
    line_width = label.length + 2
    thread = Thread.new do
      frame = 0
      while running
        print "\r#{label} #{SPINNER_FRAMES[frame % SPINNER_FRAMES.size]}"
        frame += 1
        sleep 0.1
      end
    end

    lambda do
      running = false
      thread.join
      print "\r#{' ' * line_width}\r"
    end
  end

  # ─── System prompt --------------------------------------------------------

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a coding assistant, named #{AGENT_NAME}. You help the user learn about software and write good code.

    To help you help the user, you have access to some tools. To use a tool, end
    your response with one of the following protocols, on its own line:

    PWD:                       # Get the current working directory

    LISTFILES: <glob-pattern>  # List files in the current directory, matching optional pattern

    READFILE: <file path>      # Read in the contents of a file

    WRITEFILE: <file path>
    <new contents of the file> # Write the contents of a file

    RUNCOMMAND: <bash command> # Run a bash command, see the output

    The results of the tool invocation will be inserted into the conversation, as appropriate.

    Note that it is ESSENTIAL that the tool invocation be the last thing in your
    response, with NO other text following it. And no extraneous text fencing or
    quoting.
  PROMPT

  # ─── Agent class ----------------------------------------------------------

  # A single-turn coding agent with tool use and a REPL loop.
  #
  # @param api_url      [String] base URL for the model API
  # @param model        [String] model identifier
  # @param max_tokens   [Integer] max tokens per reply
  # @param api_key      [String] authentication key
  # @param cmd_timeout  [Integer] seconds before a shell command is killed
  # @param thinking     [Boolean] whether extended thinking is enabled
  # @param sandbox_dir  [String] resolved absolute path; READFILE/WRITEFILE
  #                     may not escape this directory
  # @param max_history  [Integer] maximum number of non-system messages to
  #                     send; older turns are truncated to stay in context
  # @param log_io       [IO] where tool-execution audit log is written
  class Agent
    attr_reader :messages

    def initialize(
      api_url:     ENV.fetch("#{AGENT_NAME.upcase}_API_URL", "http://localhost:11434/v1/messages"),
      model:       ENV.fetch("#{AGENT_NAME.upcase}_MODEL", "qwen3.8:latest"),
      max_tokens:  Integer(ENV.fetch("#{AGENT_NAME.upcase}_MAX_TOKENS", 32_768)),
      api_key:     ENV.fetch("#{AGENT_NAME.upcase}_API_KEY", "ollama"),
      cmd_timeout: Integer(ENV.fetch("#{AGENT_NAME.upcase}_CMD_TIMEOUT", 120)),
      thinking:    ENV.fetch("#{AGENT_NAME.upcase}_THINKING", "on") != "off",
      sandbox_dir: File.realpath(File.expand_path(Dir.pwd)),
      max_history: Integer(ENV.fetch("#{AGENT_NAME.upcase}_MAX_HISTORY", 40)),
      log_io:      $stderr
    )
      @api_url     = api_url
      @model       = model
      @max_tokens  = max_tokens
      @api_key     = api_key
      @cmd_timeout = cmd_timeout
      @thinking    = thinking
      @sandbox_dir = File.realpath(sandbox_dir)
      @max_history = max_history
      @log_io      = log_io

      @messages = [{ role: "system", content: SYSTEM_PROMPT }]
      @assistant_message = nil
      @exit_requested = false
    end

    # Run the full REPL loop. Prints the greeting and loops until the user
    # types "exit" / "quit" or closes stdin.
    def run
      puts greeting

      # Warn if the API key looks like a placeholder and the URL is external.
      if @api_url !~ /localhost|127\.0\.0\.1/ && @api_key == "ollama"
        warn "Warning: API_KEY is set to 'ollama' (the Ollama default) but API_URL " \
             "points to an external host. Set #{AGENT_NAME.upcase}_API_KEY to a real key."
      end

      loop do
        step
        break if @exit_requested
      end

      puts "Goodbye!"
    end

    # Execute one iteration of the agent loop:
    #   1. Record the assistant's reply (if any).
    #   2. Parse and execute a tool call, or read user input.
    #   3. Send the updated history to the API.
    #
    # On API failure, rolls back both the assistant message and the tool result
    # so the conversation invariant (every tool call followed by its result) holds.
    def step
      # Snapshot message count BEFORE any pushes, so rollback on API error
      # removes both the assistant message and the tool result.
      pre_tool_count = @messages.size

      # Record the assistant's reply from the previous turn.
      @messages << { role: "assistant", content: @assistant_message } unless @assistant_message.to_s.strip.empty?

      tool_name, params = Maximilian::Parser.parse_tool_call(@assistant_message)

      execute_tool(tool_name, params)

      return if @exit_requested

      # Truncate history if it exceeds the cap.
      truncate_history

      # Build and send the API request.
      request = build_request
      begin
        @assistant_message, stop_reason = stream_reply(request)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        warn "Error: the model took too long to send the next part of its reply (#{e.class})."
        @messages = @messages[0...pre_tool_count]
        @assistant_message = nil
        stop_reason = nil
      rescue StandardError => e
        warn "Error: #{e.class}: #{e.message}"
        @messages = @messages[0...pre_tool_count]
        @assistant_message = nil
        stop_reason = nil
      end

      return unless @assistant_message.to_s.strip.empty?

      warn "(#{AGENT_NAME} sent no text, stop_reason: #{stop_reason.inspect})"
    end

    private

    def greeting
      <<~MSG
        Hi there, #{ENV.fetch("USER", nil)}! I'm your handy dandy assistant, #{AGENT_NAME}!
        What can I do for you today?
      MSG
    end

    # Dispatch a tool call. Returns nil on success. Sets @exit_requested when
    # the user types exit/quit or stdin is closed.
    def execute_tool(tool_name, params)
      case tool_name
      when "PWD"
        @messages << { role: "user", content: Dir.pwd }

      when "LISTFILES"
        @messages << { role: "user", content: list_files(params[:pattern]) }

      when "READFILE"
        @messages << { role: "user", content: read_file(params[:path]) }

      when "WRITEFILE"
        @messages << { role: "user", content: write_file(params[:path], params[:content]) }

      when "RUNCOMMAND"
        output, status = Maximilian::Shell.run_command(params[:command], @cmd_timeout)
        log_tool("RUNCOMMAND", params[:command])
        print output
        @messages << { role: "user", content: "Status: #{status}\nOutput:\n#{output}" }

      else
        @exit_requested = read_user_input?
      end
    end

    # Reads one line of user input. Returns true if the user requested exit
    # (typed "exit"/"quit" or closed stdin), false otherwise.
    def read_user_input?
      print "#{AGENT_NAME}> "
      input = gets&.chomp
      return true if input.nil?
      return true if %w[exit quit].include?(input)

      @messages << { role: "user", content: input }
      false
    end

    def list_files(pattern)
      # Glob within the sandbox directory so results are always sandbox-relative.
      files = Dir.glob(File.join(@sandbox_dir, pattern),
                       File::FNM_PATHNAME | File::FNM_DOTMATCH)
                 .first(500)
                 .reject { |f| [".", ".."].include?(File.basename(f)) }
      files.join("\n")
    end

    # Resolve a path against the sandbox and ensure it does not escape.
    # Returns the resolved absolute path, or raises if it escapes.
    def resolve_sandboxed_path(path)
      resolved = File.expand_path(path, @sandbox_dir)
      unless resolved == @sandbox_dir || resolved.start_with?(@sandbox_dir + File::SEPARATOR)
        raise ArgumentError, "path '#{path}' resolves to '#{resolved}' which is outside sandbox '#{@sandbox_dir}'"
      end

      # If the file (or any parent) is a symlink, resolve the real path and check again.
      if File.exist?(resolved)
        real = File.realpath(resolved)
        unless real == @sandbox_dir || real.start_with?(@sandbox_dir + File::SEPARATOR)
          raise ArgumentError, "path '#{path}' resolves to '#{real}' via symlink, outside sandbox"
        end
      end

      resolved
    end

    def read_file(path)
      resolved = resolve_sandboxed_path(path)
      log_tool("READFILE", resolved)
      File.read(resolved)
    rescue SystemCallError, ArgumentError => e
      "Error: could not read '#{path}': #{e.message}"
    end

    def write_file(path, content)
      resolved = resolve_sandboxed_path(path)
      log_tool("WRITEFILE", resolved)
      File.write(resolved, content)
      "File written successfully (#{resolved})."
    rescue SystemCallError, ArgumentError => e
      "Error: could not write '#{path}': #{e.message}"
    end

    def log_tool(tool_name, detail)
      ts = Time.now.strftime("%H:%M:%S")
      @log_io.puts("[#{ts}] #{tool_name} #{detail}")
    end

    def truncate_history
      # Keep the system message (index 0) plus the most recent @max_history
      # non-system messages.
      system = @messages.first
      rest = @messages[1..]
      return if rest.size <= @max_history

      dropped = rest.size - @max_history
      @messages = [system, *rest.last(@max_history)]
      log_tool("TRUNCATE", "#{dropped} old message(s) dropped")
    end

    def build_request
      req = {
        model: @model,
        max_tokens: @max_tokens,
        messages: @messages
      }
      req[:thinking] = { type: "disabled" } unless @thinking
      req
    end

    # Send the request with streaming, with retry on 5xx.
    # Returns [text, stop_reason].
    def stream_reply(request, max_retries: 3)
      attempt = 0
      loop do
        return attempt_stream(request)
      rescue Maximilian::ApiError => e
        attempt += 1
        # Retry only on 5xx server errors, and only up to max_retries.
        if attempt <= max_retries && e.message =~ /\A5\d\d /
          backoff = 2**(attempt - 1) # 1, 2, 4 seconds
          warn "API error (#{e.message.split.first}); retrying in #{backoff}s (attempt #{attempt}/#{max_retries})..."
          sleep(backoff)
          next
        end
        raise
      end
    end

    # Stream an SSE response and print text deltas as they arrive.
    # Returns [full_text, stop_reason].
    def attempt_stream(request)
      uri = URI(@api_url)
      headers = {
        "x-api-key" => @api_key,
        "anthropic-version" => "2023-06-01",
        "content-type" => "application/json"
      }
      post = Net::HTTP::Post.new(uri.path, headers)
      post.body = request.merge(stream: true).to_json

      text = +""
      stop_reason = nil
      stop_spinner = Maximilian.start_spinner("#{AGENT_NAME} thinking...")
      stop_spinner_once = lambda do
        stop_spinner&.call
        stop_spinner = nil
      end

      # read_timeout limits the gap between SSE chunks, not the whole reply.
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 1800) do |http|
        http.request(post) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            raise Maximilian::ApiError, "#{response.code} #{response.message}\n#{response.body}"
          end

          # Server-sent events, each ending in a blank line.
          # Anthropic format: single-line "data: ..." per event.
          buffer = +""
          response.read_body do |chunk|
            buffer << chunk
            while (event_end = buffer.index("\n\n"))
              data = buffer.slice!(0, event_end + 2)[/^data: (.*)$/, 1]
              next unless data

              event = JSON.parse(data)
              case event["type"]
              when "content_block_delta"
                next unless event.dig("delta", "type") == "text_delta"

                stop_spinner_once.call
                text << event.dig("delta", "text")
                print event.dig("delta", "text")
              when "message_delta"
                stop_reason = event.dig("delta", "stop_reason")
              when "error"
                raise Maximilian::ApiError, event.dig("error", "message")
              end
            end
          end
        end
      end
      puts unless text.empty? || text.end_with?("\n")
      [text, stop_reason]
    ensure
      stop_spinner_once&.call
    end
  end
end
