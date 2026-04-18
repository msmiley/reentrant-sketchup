# Manual integration tests

The automated suite in [`mcp_server_test.rb`](mcp_server_test.rb) runs outside
SketchUp with stubs. Some behaviors can only be exercised in a real SketchUp
Ruby VM — use this checklist before cutting a release.

## Setup

1. Install the extension (symlink or `.rbz`) and start SketchUp.
2. **Plugins > Reentrant SketchUp > MCP Server** to start the server.
3. From a terminal on the same machine:
   ```sh
   claude mcp add sketchup --transport http http://127.0.0.1:3636/mcp
   ```

Each scenario below lists the expected structured response. Use `jq` or your
MCP client's raw-payload view to inspect.

## 1. Normal success

```
tools/call execute_ruby { "code": "Sketchup.active_model.entities.count" }
```

Expect `status: "ok"`, `result: "<N>"`, non-zero `elapsed_ms`, `entity_count` matching `result`.

## 2. Ruby exception

```
tools/call execute_ruby { "code": "raise ArgumentError, 'oops'" }
```

Expect `status: "error"`, `error: "ArgumentError"`, `message: "oops"`, `backtrace` present, `isError: true` on the outer envelope.

Sanity-check in the SketchUp UI: **Edit > Undo** should NOT show a "MCP
execute_ruby" step (the op was aborted).

## 3. Atomicity under failure

```
tools/call execute_ruby {
  "code": "m = Sketchup.active_model; g = m.active_entities.add_group; g.entities.add_line([0,0,0],[10,0,0]); raise 'fail'"
}
```

Expect `status: "error"`. Verify in the model that no group was added and no
"MCP execute_ruby" entry appears in the Undo stack.

## 4. Transport timeout

```
tools/call execute_ruby { "code": "sleep 45", "timeout_s": 2 }
```

Expect `status: "timeout"` within ~2s. The message must say the work may still
be running and recommend calling probe.

Immediately follow up:

```
tools/call probe {}
```

`snapshot_age_ms` should be small (cache is refreshed every ~500 ms) or stale
if the pump is blocked by the sleeping eval. Either way, probe must return.

Wait 45+ seconds, then call probe again — `snapshot_age_ms` should drop back
down as the pump resumes.

## 5. probe during in-flight execute_ruby

Start a long op in one client:

```
tools/call execute_ruby {
  "code": "100.times { |i| Sketchup.active_model.active_entities.add_cpoint([i,0,0]); sleep 0.2 }",
  "timeout_s": 60
}
```

In parallel, from another client (or a second pane):

```
tools/call probe {}
```

Probe must respond immediately (sub-100 ms) with a snapshot. `source` should
be `"snapshot"`. `snapshot_age_ms` may grow as the main thread is busy —
that's the intended diagnostic.

## 6. probe with live=true waits for the main thread

During the same in-flight op:

```
tools/call probe { "live": true }
```

This should block until the long op completes (or time out). `source: "live"`
in the response.

## 7. Modal dialog blocks the VM; probe still works

Run:

```
tools/call execute_ruby { "code": "UI.messagebox('click OK to continue')" }
```

A SketchUp dialog appears. The execute_ruby call will time out at 30s.

Before clicking OK, call probe — it must return from the snapshot. Once the
dialog is dismissed, the late-completing eval commits (no UI error).

## 8. execute_ruby_file happy path

```
# On the SketchUp host:
echo 'Sketchup.active_model.entities.count' > /tmp/probe_size.rb
```

```
tools/call execute_ruby_file { "path": "/tmp/probe_size.rb" }
```

Expect `status: "ok"`, `result` matching the entity count, `source_file`
echoing the path, `source_bytes` matching the file size.

## 9. execute_ruby_file rejects relative + missing paths

```
tools/call execute_ruby_file { "path": "relative.rb" }
```
→ `status: "error"`, message mentions `absolute`.

```
tools/call execute_ruby_file { "path": "/tmp/definitely-not-there-123.rb" }
```
→ `status: "error"`, message mentions `not found`.

## 10. Backward-compat string read

A legacy client parsing the text content as a plain string will now receive
the JSON payload. The agreed migration is: `JSON.parse(text)["result"]` yields
the inspect-style string the old API returned.

```
tools/call execute_ruby { "code": "'hello'" }
```

Raw content text should be JSON; `JSON.parse(text)["result"]` must be `"\"hello\""`.

## 11. open_operations counter

Set up an un-nested op and don't commit it (simulated via Ruby Console):

```ruby
Sketchup.active_model.start_operation('leak', true)
```

Now call `tools/call probe {}`. `open_operations` should be `>= 1` in the
response. Commit or abort the op in the Ruby Console; probe should report
`0` again after the next refresh tick.

## 12. Large result truncation

```
tools/call execute_ruby { "code": "'x' * 50_000" }
```

`result` is clipped to ~4 KB + a `...[truncated, 50002 total bytes]` suffix.
