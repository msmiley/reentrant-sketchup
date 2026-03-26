# frozen_string_literal: true

module ReentrantSketchup
  unless file_loaded?(__FILE__)
    # -- Edit menu --
    edit_sub = UI.menu('Edit').add_submenu(PLUGIN_NAME)
    edit_sub.add_item('Make Unique Each') { GroupTools.make_unique_each }
    edit_sub.add_item('Trim Multiple') { GroupTools.trim_multiple }
    snap_id = edit_sub.add_item('Toggle Snapping') { SnappingTools.toggle_snapping }
    edit_sub.set_validation_proc(snap_id) {
      SnappingTools.snapping_enabled? ? MF_CHECKED : MF_UNCHECKED
    }

    # -- Tools menu: Geometry & Material operations --
    tools_sub = UI.menu('Tools').add_submenu(PLUGIN_NAME)

    geo_menu = tools_sub.add_submenu('Geometry')
    geo_menu.add_item('Total Face Area') { GeometryTools.total_face_area }
    geo_menu.add_item('Total Edge Length') { GeometryTools.total_edge_length }
    geo_menu.add_item('Selection Bounds') { GeometryTools.selection_bounds }
    geo_menu.add_item('Orient Faces') { GeometryTools.orient_faces }
    geo_menu.add_item('Level Selection') { GeometryTools.level_selection }
    geo_menu.add_item('Pull to Length') { GeometryTools.pull_to_length }

    mat_menu = tools_sub.add_submenu('Materials')
    mat_menu.add_item('Purge Unused Materials') { MaterialTools.purge_unused_materials }
    mat_menu.add_item('List Materials') { MaterialTools.list_materials }

    lay_menu = tools_sub.add_submenu('Layers/Tags')
    lay_menu.add_item('Show All Layers') { LayerTools.show_all_layers }
    lay_menu.add_item('List Layers') { LayerTools.list_layers }

    # -- Camera menu: View operations --
    cam_sub = UI.menu('Camera').add_submenu(PLUGIN_NAME)
    cam_sub.add_item('Zoom Selection') { CameraTools.zoom_selection }

    # -- Context menu: Rotate 90° & Duplicate --
    RotationTools.register_context_menu
    DuplicateTools.register_context_menu

    # -- Extensions menu: Update check --
    ext_menu = UI.menu('Plugins').add_submenu(PLUGIN_NAME)
    ext_menu.add_item('Check for Updates...') { Updater.check_for_update(notify_if_current: true) }

    file_loaded(__FILE__)
  end
end
