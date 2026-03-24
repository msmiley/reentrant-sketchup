# frozen_string_literal: true

module ReentrantSketchup
  module CameraTools
    # Zoom the camera to fit the current selection.
    def self.zoom_selection
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      view = model.active_view
      view.zoom(selection)
      puts "Zoomed to selection (#{selection.count} entities)"
    end

    # Zoom the camera to fit all entities in the model.
    def self.zoom_extents
      Sketchup.active_model.active_view.zoom_extents
      puts 'Zoomed to extents'
    end

    # Save the current camera position as a named scene/page.
    def self.save_view_as_scene(name)
      model = Sketchup.active_model
      model.start_operation('Save Scene', true)
      page = model.pages.add(name)
      page.use_camera = true
      model.commit_operation
      puts "Saved current view as scene '#{name}'"
      page
    end

    # Set the camera to a standard top-down view.
    def self.top_view
      model = Sketchup.active_model
      camera = model.active_view.camera
      bounds = model.bounds
      center = bounds.center
      eye = Geom::Point3d.new(center.x, center.y, center.z + [bounds.diagonal, 100].max)
      target = center
      up = Geom::Vector3d.new(0, 1, 0)
      camera.set(eye, target, up)
      camera.perspective = false
      model.active_view.zoom_extents
      puts 'Switched to top view'
    end

    # Set the camera to a standard front view.
    def self.front_view
      model = Sketchup.active_model
      camera = model.active_view.camera
      bounds = model.bounds
      center = bounds.center
      eye = Geom::Point3d.new(center.x, center.y - [bounds.diagonal, 100].max, center.z)
      target = center
      up = Geom::Vector3d.new(0, 0, 1)
      camera.set(eye, target, up)
      camera.perspective = false
      model.active_view.zoom_extents
      puts 'Switched to front view'
    end

    # Toggle between perspective and parallel projection.
    def self.toggle_perspective
      camera = Sketchup.active_model.active_view.camera
      camera.perspective = !camera.perspective?
      mode = camera.perspective? ? 'Perspective' : 'Parallel Projection'
      puts "Camera: #{mode}"
    end
  end
end
