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

  end
end
