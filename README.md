# Reentrant SketchUp

A SketchUp extension providing a collection of frequently used operations, accessible from the **Plugins > Reentrant SketchUp** menu.

## Installation

1. Copy `src/reentrant_sketchup.rb` and the `src/reentrant_sketchup/` folder into your SketchUp Plugins directory:
   - **Windows:** `C:\Users\<name>\AppData\Roaming\SketchUp\SketchUp <version>\SketchUp\Plugins\`
   - **macOS:** `~/Library/Application Support/SketchUp <version>/SketchUp/Plugins/`
2. Restart SketchUp.
3. Enable the extension via **Window > Extension Manager** if it isn't auto-enabled.

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
