# Changelog

## 1.7.0 — MCP reliability pass

`execute_ruby` no longer hangs clients for ~4 minutes when things go wrong. It
also never leaves the model half-committed on error. New tools (`probe`,
`execute_ruby_file`) and a main-thread-refreshed snapshot cache make the
server observable and responsive even when the Ruby VM is blocked.

### Added

- `probe` tool — fast diagnostic read (title, path, entity counts, active
  context, `open_operations`, `extension_version`). Default path reads from a
  frozen snapshot cache on the worker thread, so it responds immediately
  even when `execute_ruby` is stuck. Every response includes `fetched_at_ms`
  and `snapshot_age_ms` so clients can reason about staleness. Pass
  `live: true` to route through the main thread for a ground-truth read.
- `execute_ruby_file` tool — reads a Ruby script from an absolute path on
  the SketchUp host and runs it through the same hardened pipeline as
  `execute_ruby`. Useful for scripts too large for the transport and for
  debugging (the file stays on disk). Refuses relative paths; caps size at
  1 MB; returns `source_file` / `source_bytes` alongside the usual fields.
- `op_name`, `wrap_op`, `timeout_s` arguments on `execute_ruby` (and matching
  options on `execute_ruby_file`).
- `test/mcp_server_test.rb` — 27 automated cases runnable outside SketchUp.
- `test/manual.md` — checklist for scenarios that only repro inside SketchUp
  (modal dialogs, atomicity on failure, live probe during an in-flight op).

### Changed

- `execute_ruby` now wraps execution in a SketchUp undo operation by default
  and aborts on any exception, so a failing script never leaves partial
  geometry behind.
- Every tool returns a structured JSON payload with a `status` field
  (`ok` / `error` / `timeout` / `pending`). Text content is pretty-printed
  JSON; the outer MCP envelope sets `isError: true` for error and timeout
  statuses.
- Transport timeout defaults to **30 seconds** (was unbounded in practice —
  the previous loop used `cv.wait(mutex, 30) until done`, which simply
  re-waited forever). A timeout returns `status: "timeout"` with the elapsed
  time and tool name; the underlying Ruby work continues (SketchUp cannot
  safely interrupt it). Override per-call with `timeout_s`; clamped to
  `[1, 600]`.
- HTTP write path coalesced to a single `client.write` and `TCP_NODELAY` set
  on accepted sockets, so a timeout response reaches the wire immediately
  without waiting for Nagle or for the still-running main-thread eval.
  End-to-end test (`test/mcp_server_test.rb`) asserts the timeout response
  arrives within `timeout_s + 500 ms` over keep-alive while the pump is
  blocked in `sleep`.

### Backward compatibility

Clients that read the tool result's `text` content as a plain string now
receive JSON. The migration is one line: `JSON.parse(text)["result"]` yields
the inspect-style string the old API returned.

### Known limitations

- `Timeout::timeout` is intentionally not used: in SketchUp's single-threaded
  Ruby VM it cannot interrupt a C-level API call (boolean ops, entity
  iteration) running on the main thread. The server-side response-wait
  timeout is the real backstop; it stops waiting but does not cancel the
  work. Use `probe` to verify state before retrying.
- Modal SketchUp dialogs still freeze the Ruby VM. `probe` remains responsive
  (a growing `snapshot_age_ms` is the signal), but dismissing the dialog
  requires a human. Auto-dismissal is out of scope.

## 1.6.2

- Fix MCP keep-alive: support multiple requests per TCP connection.

## 1.6.1

- Fix MCP connection drops — notifications, CORS, protocol version.

## 1.6.0

- Add MCP server for Claude Code integration.

## 1.5.x

- Rotate 90° uses local component axes when a single instance is selected.
