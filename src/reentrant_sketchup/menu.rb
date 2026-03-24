# frozen_string_literal: true

module ReentrantSketchup
  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu(PLUGIN_NAME)

    # -- Selection --
    sel_menu = menu.add_submenu('Selection')
    sel_menu.add_item('Select All Edges') { SelectionTools.select_all_edges }
    sel_menu.add_item('Select All Faces') { SelectionTools.select_all_faces }
    sel_menu.add_item('Select All Groups') { SelectionTools.select_all_groups }
    sel_menu.add_item('Select All Components') { SelectionTools.select_all_components }
    sel_menu.add_item('Select Connected') { SelectionTools.select_connected }
    sel_menu.add_item('Invert Selection') { SelectionTools.invert_selection }

    # -- Geometry --
    geo_menu = menu.add_submenu('Geometry')
    geo_menu.add_item('Total Face Area') { GeometryTools.total_face_area }
    geo_menu.add_item('Total Edge Length') { GeometryTools.total_edge_length }
    geo_menu.add_item('Selection Bounds') { GeometryTools.selection_bounds }
    geo_menu.add_item('Orient Faces') { GeometryTools.orient_faces }

    # -- Groups & Components --
    grp_menu = menu.add_submenu('Groups && Components')
    grp_menu.add_item('Group Selection') { GroupTools.group_selection }
    grp_menu.add_item('Explode Selection') { GroupTools.explode_selection }
    grp_menu.add_item('Group to Component') { GroupTools.group_to_component }
    grp_menu.add_item('Lock Selection') { GroupTools.lock_selection }
    grp_menu.add_item('Unlock Selection') { GroupTools.unlock_selection }
    grp_menu.add_item('Purge Empty Groups') { GroupTools.purge_empty_groups }

    # -- Layers/Tags --
    lay_menu = menu.add_submenu('Layers/Tags')
    lay_menu.add_item('Show All Layers') { LayerTools.show_all_layers }
    lay_menu.add_item('List Layers') { LayerTools.list_layers }

    # -- Materials --
    mat_menu = menu.add_submenu('Materials')
    mat_menu.add_item('Purge Unused Materials') { MaterialTools.purge_unused_materials }
    mat_menu.add_item('List Materials') { MaterialTools.list_materials }

    # -- Camera --
    cam_menu = menu.add_submenu('Camera')
    cam_menu.add_item('Zoom Selection') { CameraTools.zoom_selection }
    cam_menu.add_item('Zoom Extents') { CameraTools.zoom_extents }
    cam_menu.add_item('Top View') { CameraTools.top_view }
    cam_menu.add_item('Front View') { CameraTools.front_view }
    cam_menu.add_item('Toggle Perspective') { CameraTools.toggle_perspective }

    file_loaded(__FILE__)
  end
end
