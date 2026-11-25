---

## 🔴 High Priority

### 1. `parse_tool_call` reaches into `$~` — fragile and non-obvious
**Avdi:** After a `case/when` with a regex, `$~` is the *last successful match in the entire thread*. Today this works because only one `when` fires. But the moment you add a `when` that does its own `=~` or `match?` before the `case`, `$~` gets clobbered and you get a silent nil. This is a hidden temporal coupling.

**Jessica:** Our tests pass *today*, but they don't guard against the refactor that breaks it. A test that adds a second regex-matching `when` would catch it — we have none.

```text
[ ] Refactor parse_tool_call to capture named groups into locals
    immediately inside each when branch, never read $~ outside the match.
[ ] Extract each tool's parsing into a small, independently testable
    method or class: ToolParser#parse("PWD:") -> ToolCall.
[ ] Add a test: add a dummy when branch that does a match?, then
    verify PWD still parses correctly.
```

### 2. `messages.pop` on HTTP error can corrupt conversation state
**Avdi:** After a tool executes successfully, we push *two* things: the assistant message (with the tool call) and the tool result. Then the HTTP request fails. We pop *one* message — the tool result — but the assistant message (which contains the tool call) is still in the array. Next iteration we re-send a message that claims "I called PWD" but the result is gone. The model gets a confused history.

**Jessica:** This is a state-machine bug. The loop has an implicit invariant: *every tool call in the history must be followed by its result.* Nothing tests that invariant.

```text
[ ] On HTTP failure, pop BOTH the assistant message and the tool result
    (or restructure so the tool result is only pushed after a successful
    HTTP response).
[ ] Add a test that simulates: assistant message with tool call →
    tool result pushed → HTTP 500 → assert messages array is back to
    its pre-tool-call state.
[ ] Consider wrapping the "push assistant + execute tool + push result"
    in a transaction-like guard.
```

### 3. `run_command` returns `nil` status on `SystemCallError` — callers crash
**Avdi:** The rescue returns `[..., nil]`. But the caller does `status.exitstatus`. That's a `NoMethodError` on `nil` that will crash the loop. The error message the model gets is a raw Ruby traceback.

**Jessica:** We have a test for `run_command` failing (non-zero exit) but *not* for the `SystemCallError` path (command doesn't exist, permission denied). That's an untested branch that will hit the user.

```text
[ ] Decide: does run_command ever return nil for status? Either make it
    impossible (return a synthetic status), or make the caller handle nil.
[ ] Add a test: run_command("nonexistent_xyz", 10) and assert the
    output contains an error message and the caller doesn't crash.
```

### 4. No path sandboxing on READFILE / WRITEFILE
**Avdi:** `File.read(path)` and `File.write(path, ...)` take the raw string from the model. `../../etc/passwd`, `/dev/null`, symlink chains — all live. The confirmation prompt is the *only* guard, and a user skimming "rodger wants to write /Users/max/.bashrc" might hit `y` without thinking.

**Jessica:** This is the highest-blast-radius surface in the system. Our tests use `Dir.mktmpdir` which is great, but we have *zero* tests that assert "you can't escape the sandbox."

```text
[ ] Add a path-resolution step: resolve the path against a working
    directory, reject if the resolved path escapes it.
[ ] Add tests: READFILE "../../etc/passwd" → denied. WRITEFILE to a
    symlink that escapes the sandbox → denied.
[ ] At minimum, print the *resolved absolute path* in the confirmation
    prompt so the user sees where it really goes.
```

---

## 🟡 Medium Priority

### 5. Top-level mutable state: `messages`, `assistant_message`
**Avdi:** These are global-ish variables. The loop's behavior depends on their current value, but that value isn't passed in or returned — it's *read and mutated in place*. This is the "state is a hidden parameter" anti-pattern. It's why we had to add the `__FILE__` guard.

**Jessica:** It means the loop can't be tested without either (a) running the whole thing or (b) reaching in and mutating globals. Our `TestLoad` smoke tests are the best we can do, and they're weak.

```text
[ ] Extract the loop into a class: Agent#run, Agent#step, with
    @messages as an instance variable.
[ ] Agent.new(api_url:, model:, cmd_timeout:) — inject dependencies.
[ ] Test Agent#step in isolation: give it a mock HTTP response, assert
    the next message in @messages.
```

### 6. `Dir.glob` with `FNM_DOTMATCH` matches `.` and `..`
**Avdi:** `FNM_DOTMATCH` means hidden files *and* `.`/`..`. Listing `.` and `..` is noise the model has to wade through. `FNM_FILE_NAME` or a post-filter would be cleaner.

**Jessica:** A test that creates a temp dir with `.` and `..` and checks the glob output would catch this. We don't have one.

```text
[ ] Filter out "." and ".." from the glob results.
[ ] Add a test: glob in a dir with subdirs, assert "." and ".." absent.
```

### 7. `SPINNER_FRAMES` and other constants aren't frozen
**Avdi:** A `warn` at load time is a side effect in what should be a pure config block. And an unfrozen array constant is an invitation to accidental mutation.

**Jessica:** Not a correctness issue, but a "what's the blast radius of a bad edit" issue.

```text
[ ] Add `# frozen_string_literal: true` magic comment.
[ ] Freeze SPINNER_FRAMES: SPINNER_FRAMES = %w[| / - \\].freeze
[ ] Move the API-key warning into the main-loop block (after the
    __FILE__ guard) so requiring the file is side-effect-free.
```

### 8. No conversation truncation / context management
**Avdi:** `messages` grows unboundedly. After 50 turns you're sending the entire history every time, which wastes tokens and can exceed the model's context window silently (the API just truncates or errors).

**Jessica:** We have no test that asserts "after N turns, the message count is bounded." The system will degrade in a way we can't observe from the test suite.

```text
[ ] Add a max-message-count or token-budget cap.
[ ] Log a warning when truncation happens.
[ ] Test: simulate 100 turns, assert messages array stays bounded.
```

---

## 🟢 Low Priority / Polish

### 9. Confirmation prompt only accepts `"y"`
```text
[ ] Accept "y", "yes", "Y" — or at minimum, be case-insensitive.
[ ] Add a test for the confirmation logic (extract it from the loop).
```

### 10. `WRITEFILE` always appends `\n` to content
**Avdi:** `content: "#{$~[:content]}\n"` — this means a file that was supposed to end without a trailing newline now has one. Surprising.

**Jessica:** Our round-trip test asserts the `\n` is there, so we've *locked in* the behavior. But is it the *right* behavior?

```text
[ ] Decide: is the trailing newline intentional? Document it.
[ ] If it's a convention, name it: content: with_newline(content).
```

### 11. `Net::HTTP` with a 600-second read timeout and no retry
**Jessica:** One 500 from Ollama kills the turn. A transient network blip loses the user's context.

```text
[ ] Add a retry-with-backoff for 5xx responses (3 attempts, 1s/2s/4s).
[ ] Test: mock a 503 then a 200, assert the retry succeeds.
```

### 12. No logging / audit trail
**Jessica:** If the agent does something destructive, there's no record. `print` to stdout is not a log.

```text
[ ] Add a simple log file (timestamped) for tool executions.
[ ] At minimum, log READFILE/WRITEFILE/RUNCOMMAND to stderr.
```

### 13. `parse_tool_call` could use a table-driven design
**Avdi:** Five `when` branches that all follow the same shape (regex → extract named group → return `[name, {key: value}]`). A small registry or a data table would be more extensible and testable.

```text
[ ] Define TOOLS as a hash: { "PWD" => { regex: /.../ }, ... }
[ ] parse_tool_call iterates the registry.
[ ] Each tool's parse logic is a testable unit.
```

### 14. Add a `.rubocop.yml` and run it
**Avdi:** Lints catch the frozen-constant, string-literal, and style issues automatically.

```text
[ ] Init rubocop, enable style + performance cop.
[ ] Fix what it flags.
[ ] Add to the test harness: rubocop agent.rb test_agent.rb
```

---

## Suggested Order of Attack

| Priority | Item | Est. effort |
|---|---|---|
| 🔴 2 | Fix `messages.pop` corruption on HTTP error | 30 min |
| 🔴 3 | Fix `nil` status crash in `run_command` | 15 min |
| 🔴 1 | Stop reading `$~` in `parse_tool_call` | 30 min |
| 🔴 4 | Path sandboxing for READFILE/WRITEFILE | 1 hr |
| 🟡 5 | Extract loop into `Agent` class | 2 hrs |
| 🟡 6 | Filter `.`/`..` from glob | 10 min |
| 🟡 7 | Freeze constants, move side effects | 15 min |
| 🟡 8 | Conversation truncation | 45 min |
| 🟢 9–14 | Polish | 1–2 hrs |
