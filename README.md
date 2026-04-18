# Reentrant SketchUp

A SketchUp extension providing a collection of frequently used operations, accessible from the **Plugins > Reentrant SketchUp** menu.

## Installation

1. Copy `src/reentrant_sketchup.rb` and the `src/reentrant_sketchup/` folder into your SketchUp Plugins directory:
   - **Windows:** `C:\Users\<name>\AppData\Roaming\SketchUp\SketchUp <version>\SketchUp\Plugins\`
   - **macOS:** `~/Library/Application Support/SketchUp <version>/SketchUp/Plugins/`
2. Restart SketchUp.
3. Enable the extension via **Window > Extension Manager** if it isn't auto-enabled.

### Dev Installation

```sh
ln -s /path/to/reentrant-sketchup/src/reentrant_sketchup.rb \
  ~/Library/Application\ Support/SketchUp\ 2026/SketchUp/Plugins/reentrant_sketchup.rb

ln -s /path/to/reentrant-sketchup/src/reentrant_sketchup \
  ~/Library/Application\ Support/SketchUp\ 2026/SketchUp/Plugins/reentrant_sketchup
```

## Modules

### Selection Tools
| Command | Description |
|---------|-------------|
| Select All Edges | Select every edge in the active context |
| Select All Faces | Select every face in the active context |
| Select All Groups | Select every group in the active context |
| Select All Components | Select every component instance in the active context |
| Select Connected | Flood-select all entities connected to the current selection |
| Invert Selection | Invert the current selection |

### Geometry Tools
| Command | Description |
|---------|-------------|
| Total Face Area | Sum the area of all selected faces |
| Total Edge Length | Sum the length of all selected edges |
| Selection Bounds | Report width, depth, and height of selection bounding box |
| Orient Faces | Reverse faces so normals point outward |

### Group & Component Tools
| Command | Description |
|---------|-------------|
| Group Selection | Wrap selected entities in a new group |
| Explode Selection | Explode groups/components one level |
| Group to Component | Convert selected groups into component definitions |
| Lock / Unlock Selection | Lock or unlock selected groups and components |
| Purge Empty Groups | Remove all empty groups and components |

### Layer/Tag Tools
| Command | Description |
|---------|-------------|
| Show All Layers | Make all layers visible |
| List Layers | Print all layers with entity counts to the console |

Layer tools also available via the Ruby Console:
```ruby
ReentrantSketchup::LayerTools.move_to_layer('My Tag')
ReentrantSketchup::LayerTools.select_by_layer('My Tag')
ReentrantSketchup::LayerTools.toggle_layer('My Tag')
ReentrantSketchup::LayerTools.isolate_layer('My Tag')
```

### Material Tools
| Command | Description |
|---------|-------------|
| Purge Unused Materials | Remove all materials not applied to any entity |
| List Materials | Print all materials with color and usage info |

Material tools also available via the Ruby Console:
```ruby
ReentrantSketchup::MaterialTools.apply_material('Brick')
ReentrantSketchup::MaterialTools.create_color_material('Custom Red', 200, 50, 50)
ReentrantSketchup::MaterialTools.select_by_material('Brick')
```

### Camera Tools
| Command | Description |
|---------|-------------|
| Zoom Selection | Zoom camera to fit the current selection |

### Rotation Tools (Context Menu)
Right-click any selection to access **Rotate 90°**:
| Command | Description |
|---------|-------------|
| Red Axis (X) | Rotate selection 90° around the X axis |
| Green Axis (Y) | Rotate selection 90° around the Y axis |
| Blue Axis (Z) | Rotate selection 90° around the Z axis |

### MCP Server (Claude Code integration)

The extension can expose a local MCP (Model Context Protocol) server so Claude Code and other MCP clients can drive SketchUp directly.

**Start/stop:** **Plugins > Reentrant SketchUp > MCP Server** (checkmark shows when running). Listens on `http://127.0.0.1:3636/mcp` by default.

**Connect from Claude Code:**
```
claude mcp add sketchup --transport http http://127.0.0.1:3636/mcp
```

**Available tools:**
| Tool | Description |
|------|-------------|
| `probe` | Fast diagnostic snapshot (title, path, counts, active context, `open_operations`). Reads a cache on the worker thread by default; always responds even when the main thread is blocked. Pass `live: true` for a ground-truth read. |
| `get_selection` | Current selection count and entity types |
| `get_model_info` | Model path, entity/definition/material/layer counts |
| `list_entities` | List entities in the active context |
| `execute_ruby` | Evaluate arbitrary Ruby in the SketchUp context. Atomic by default — wraps execution in a SketchUp undo op and aborts on any exception. Accepts `op_name`, `wrap_op`, `timeout_s`. |
| `execute_ruby_file` | Read a Ruby script from an absolute host path and execute it through the same hardened pipeline. Useful for scripts too large for the transport. |
| `create_box` | Create a rectangular solid at given origin + dimensions |

Every response is pretty-printed JSON with a `status` field (`ok` / `error` /
`timeout` / `pending`). Error and timeout responses set `isError: true` on the
outer MCP envelope. See [CHANGELOG.md](CHANGELOG.md) for the full response
shape of each tool.

All SketchUp-touching operations run on the main thread (marshalled through a
queue pumped by `UI.start_timer`) to stay thread-safe. `probe` is the only
exception — it reads a snapshot published by the pump, so it can respond from
a worker thread without waiting on the queue.

### Troubleshooting

**I got a `status: "timeout"` response. Did my Ruby code actually run?**
Maybe. A server-side timeout stops the client from waiting but does **not**
cancel the queued work — SketchUp cannot safely interrupt a Ruby script
mid-execution. Call `probe` immediately to check current state before
retrying; retrying blindly can produce duplicate geometry.

**`probe` shows `snapshot_age_ms` growing without bound.**
The main thread is blocked. Common causes: an `execute_ruby` script with a
runaway loop, a SketchUp modal dialog waiting for human input, or a slow
boolean operation. The snapshot cache stops being refreshed while the main
thread is busy, and a stale `snapshot_age_ms` is the intended diagnostic.

**A modal SketchUp dialog is up and the server looks dead.**
`probe` will still respond (from the cache), but no tool that touches the
model can run until a human dismisses the dialog. Auto-dismissal is
intentionally out of scope.

**My long-running script always times out at 30s.**
Raise the per-call budget: pass `"timeout_s": 120` (or up to 600) in the
tool arguments. Note this only extends how long the MCP client will wait
for a response; it does not change how long SketchUp is willing to spend
running your code.

**I need to run a script too large to fit in the transport.**
Put it on disk and call `execute_ruby_file` with an absolute path. The file
stays on disk, which is also easier to debug than inlined Ruby.

## Ruby Console Usage

All tools are accessible from the SketchUp Ruby Console:

```ruby
ReentrantSketchup::SelectionTools.select_all_faces
ReentrantSketchup::GeometryTools.total_face_area
ReentrantSketchup::GroupTools.group_selection
ReentrantSketchup::CameraTools.zoom_selection
```

## License

MIT
