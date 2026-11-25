# AGENTS.md

Guidance for AI coding agents (and new humans) working on **maximilian**.

## What this is

Maximilian is a CLI coding agent. It streams a reply from an
Anthropic-Messages-API-compatible model, parses a *tool call* out of the tail
of that reply, executes it locally, appends the result to the conversation, and
loops. See [README.md](README.md) for the user-facing view.

Code lives under `lib/maximilian/`; tests under `test/maximilian/`.

## How to run

```sh
bundle install
rake test       # minitest suite (must stay at 0 failures / 0 errors)
rake rubocop    # lint; must report "no offenses"
ruby -c lib/maximilian/agent.rb   # quick syntax check
printf 'exit\n' | ruby -Ilib bin/maximilian   # smoke-test the CLI
```

A change is not done until `rake test` and `rake rubocop` are both green.

## Conventions

- Ruby ≥ 3.0. Every source file starts with `# frozen_string_literal: true`.
- **Double-quoted strings** are the house style (`Style/StringLiterals` is
  disabled in `.rubocop.yml` — do not re-enable it or mass-convert to single
  quotes).
- Public behavior lives in modules/classes under `Maximilian`. `Parser` and
  `Shell` are stateless `module_function` sets; `Agent` holds conversation
  state and takes all configuration via keyword args in `initialize`.
- `require` order matters: `version.rb` must load before `agent.rb`, because
  `SYSTEM_PROMPT`'s heredoc interpolates `Maximilian::AGENT_NAME`.

## Invariants — do not break these

These are the properties the test suite guards. If your change threatens one,
update or add a test.

1. **Conversation integrity / rollback.** In `Agent#step`, every tool call that
   appears in the history must be followed by its result. A snapshot of
   `@messages.size` is taken *before* the assistant message is pushed, and on
   any API error the array is truncated back to that snapshot
   (`@messages = @messages[0...pre_tool_count]`). Do **not** revert this to a
   single `messages.pop` — that leaves a dangling assistant message with no
   result. See `TestRollback`.

2. **Path sandbox.** `READFILE`/`WRITEFILE` resolve through
   `resolve_sandboxed_path`, which expands the path against `@sandbox_dir` and
   rejects anything that escapes (via `..` or via a symlink, checked with
   `File.realpath`). Errors from `read_file`/`write_file` are returned as
   strings, not raised, so one bad tool call can't crash the loop. See
   `TestSandbox`.

3. **`run_command` status is always a `String`.** It is never `nil` — spawn
   failure returns `"error"`, timeout returns a `"killed ..."` string, and a
   normal exit returns `exitstatus.to_s`. Callers interpolate it directly.

4. **No `$~` outside a match.** `parse_tool_call` uses sequential
   `if (m = text.match(...))` blocks and reads groups from the local `m`.
   Do not reintroduce a `case/when` regex that reads `$~` in the body — a
   later `match?`/`=~` can clobber it. See `test_parse_tool_call_unaffected_by_prior_match`.

5. **Sandbox-relative `LISTFILES`.** `list_files` globs inside `@sandbox_dir`
   and rejects `.` / `..`. See `TestListFilesFilter`.

6. **History is bounded.** `truncate_history` keeps the system message plus the
   most recent `max_history` messages. See `TestTruncation`.

## How to add a new tool

1. Add a branch to `Maximilian::Parser.parse_tool_call` (an `if (m = ...)`
   block returning `["NAME", { params }]`).
2. Add a `when "NAME"` branch in `Agent#execute_tool`, and implement a private
   helper that returns a result **string** appended as a `user` message.
3. Mention the tool in `SYSTEM_PROMPT`.
4. Add parser tests and, if it touches the filesystem, sandbox tests.
5. Run `rake test` and `rake rubocop`.

## What to avoid

- Don't make `Agent` harder to instantiate: keep all config on keyword args so
  it can be constructed in tests with fakes (e.g. a bad `api_url` to force a
  rollback).
- Don't reintroduce top-level side effects in the loaded files — the
  API-key warning lives inside `Agent#run` (the `__FILE__ == $PROGRAM_NAME`
  entry point), so `require "maximilian"` stays side-effect free.
- `attempt_stream` and `Agent` intentionally exceed the usual rubocop metric
  limits (SSE parsing, the tool dispatch table, DI constructor). The limits in
  `.rubocop.yml` are set just above the real values; don't loosen them further
  without a reason.
- The gemspec's `s.files` is `Dir["lib/**/*.rb", "bin/*", "README.md",
  "LICENSE"]` — only those ship in the gem. `AGENTS.md`, `code-review.md`,
  `Rakefile`, and `test/**` are development-only.
