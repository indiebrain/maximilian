# maximilian

⚠️ ** Warning:** This is currently a learning tool / toy and can decide to do
dangerous things if left to its own devices. Discretion is advised when using
this program.

Maximilian is an AI agent written in the Ruby programming language. It streams
replies from a model API, parses tool calls out of the model's text, executes
them, and feeds the results back into the conversation — looping until you say
`exit`.

It talks to any [Anthropic Messages API]-compatible endpoint, including [Ollama]
running an Anthropic-compatible server.

[Anthropic Messages API]: https://docs.anthropic.com/en/api/messages
[Ollama]: https://ollama.com

## Origins

Maximiilian started as a ~100-line single-file CLI script using only the Ruby
standard library - it is a tool used by its author to learn about the internals
of AI agents. In the beginning, Maximilian contained just 3 core features:

1. A Read-Eval-Print Loop (REPL)
2. A Memory (RAM based)
3. Rudimentary tool dispatching. (A standard branch and call structure)

Maximilian was then given 4 tools basic tools: List file system contents, Read
file, Write file, and Execute command. From there, Maximilian has learned about
itself and has been gently guided - by human hands - to restructure and improve
itself into this Gem.

## Features

- **Streaming replies** — text prints token-by-token as it arrives; a spinner
  covers the time the model spends "thinking."
- **Five built-in tools** — `PWD`, `LISTFILES`, `READFILE`, `WRITEFILE`,
  `RUNCOMMAND`, invoked by a simple text protocol.
- **Path sandboxing** — `READFILE`/`WRITEFILE` cannot escape the working
  directory, including via `..` or symlinks.
- **Bounded context** — the conversation history is capped to keep requests
  within the model's context window.
- **Conversation integrity** — on any API error, the assistant message and its
  tool result are rolled back together, so the history stays well-formed.
- **Resilient** — retries `5xx` API responses with exponential backoff;
  kills runaway shell commands after a timeout.
- **Audit log** — every tool execution is timestamped to stderr.

## Installation

From a checkout:

```sh
bundle install
bin/maximilian
```

Or install as a gem (once published):

```sh
gem install maximilian
maximilian
```

## Usage

```sh
$ maximilian
Hi there, max! I'm your handy dandy assistant, maximilian!
What can I do for you today?

maximilian> List the Ruby files here
<maximilian streams its reply and invokes tools...>
maximilian> exit
Goodbye!
```

Maximilian can **run arbitrary shell commands on your machine**
(`RUNCOMMAND`) and read/write files (`READFILE`/`WRITEFILE`). It is a
powerful, untrusted-input tool: review what it does, and run it in a sandbox
or project directory you can afford to affect.

## Configuration

All settings are read from environment variables (prefixed
`MAXIMILIAN_`), with sensible defaults for a local Ollama setup.

| Variable                  | Default                                   | Description |
|---------------------------|-------------------------------------------|-------------|
| `MAXIMILIAN_API_URL`      | `http://localhost:11434/v1/messages`      | Model API endpoint |
| `MAXIMILIAN_MODEL`        | `qwen3.8:latest`                          | Model identifier |
| `MAXIMILIAN_MAX_TOKENS`   | `32768`                                   | Max tokens per reply |
| `MAXIMILIAN_API_KEY`      | `ollama`                                  | Authentication key |
| `MAXIMILIAN_CMD_TIMEOUT`  | `120`                                     | Seconds before a shell command is killed |
| `MAXIMILIAN_THINKING`     | `on`                                      | Set to `off` for faster replies with weaker reasoning |
| `MAXIMILIAN_MAX_HISTORY`  | `40`                                      | Max non-system messages sent per request |

If the API key is left at the Ollama default (`ollama`) but the URL points
to a non-localhost host, Maximilian prints a warning at startup.

## Tools

Maximilian uses a text protocol: the model ends its reply with one of the
following on its own line.

| Tool | Form | Effect |
|------|------|--------|
| `PWD` | `PWD:` | Reports the current working directory |
| `LISTFILES` | `LISTFILES: <glob>` | Lists files in the sandbox matching the glob (default `*`) |
| `READFILE` | `READFILE: <path>` | Reads a file (sandboxed) |
| `WRITEFILE` | `WRITEFILE: <path>\n<contents>` | Writes a file (sandboxed) |
| `RUNCOMMAND` | `RUNCOMMAND: <bash>` | Runs a shell command with a timeout |

The result of each tool is inserted back into the conversation. The tool call
must be the last thing in the model's reply, with no trailing text, fence, or
quoting.

## Development

```sh
bundle install
rake test       # run the minitest suite
rake rubocop    # lint (rubocop must be in the Gemfile group)
rake            # test + rubocop
```

The suite covers the parser, shell execution, path sandboxing, history
truncation, and conversation rollback on API error.

## Project layout

```
bin/maximilian        Entry point
lib/maximilian.rb     Loads the library (version → parser → shell → agent)
lib/maximilian/
  version.rb          VERSION and AGENT_NAME constants
  parser.rb           parse_tool_call
  shell.rb            run_command
  agent.rb            Agent class: REPL, sandbox, truncation, streaming, retry
test/                 minitest suite, split by concern
```

## License

MIT — see [LICENSE](LICENSE).
