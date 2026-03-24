# frozen_string_literal: true

module ReentrantSketchup
  unless file_loaded?(__FILE__)
    # -- Edit menu: Selection & Group operations --
    edit_sub = UI.menu('Edit').add_submenu(PLUGIN_NAME)

    sel_menu = edit_sub.add_submenu('Selection')
    sel_menu.add_item('Select All Edges') { SelectionTools.select_all_edges }
    sel_menu.add_item('Select All Faces') { SelectionTools.select_all_faces }
    sel_menu.add_item('Select All Groups') { SelectionTools.select_all_groups }
    sel_menu.add_item('Select All Components') { SelectionTools.select_all_components }
    sel_menu.add_item('Select Connected') { SelectionTools.select_connected }
    sel_menu.add_item('Invert Selection') { SelectionTools.invert_selection }

    grp_menu = edit_sub.add_submenu('Groups && Components')
    grp_menu.add_item('Group Selection') { GroupTools.group_selection }
    grp_menu.add_item('Explode Selection') { GroupTools.explode_selection }
    grp_menu.add_item('Group to Component') { GroupTools.group_to_component }
    grp_menu.add_item('Lock Selection') { GroupTools.lock_selection }
    grp_menu.add_item('Unlock Selection') { GroupTools.unlock_selection }
    grp_menu.add_item('Make Unique Each') { GroupTools.make_unique_each }
    grp_menu.add_item('Trim Multiple') { GroupTools.trim_multiple }
    grp_menu.add_item('Purge Empty Groups') { GroupTools.purge_empty_groups }

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
    cam_sub.add_item('Zoom Extents') { CameraTools.zoom_extents }
    cam_sub.add_item('Top View') { CameraTools.top_view }
    cam_sub.add_item('Front View') { CameraTools.front_view }
    cam_sub.add_item('Toggle Perspective') { CameraTools.toggle_perspective }

    # -- Extensions menu: Update check --
    ext_menu = UI.menu('Plugins').add_submenu(PLUGIN_NAME)
    ext_menu.add_item('Check for Updates...') { Updater.check_for_update(notify_if_current: true) }

    file_loaded(__FILE__)
  end
end
