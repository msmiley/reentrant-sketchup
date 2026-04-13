# frozen_string_literal: true

module ReentrantSketchup
  module RotationTools
    GLOBAL_AXES = {
      'Red Axis (X)'   => Geom::Vector3d.new(1, 0, 0),
      'Green Axis (Y)' => Geom::Vector3d.new(0, 1, 0),
      'Blue Axis (Z)'  => Geom::Vector3d.new(0, 0, 1)
    }.freeze

    # Return the rotation axes for the current selection.
    # If a single component instance or group is selected, use its local axes
    # extracted from the instance transformation. Otherwise use global axes.
    def self.axes_for_selection
      model = Sketchup.active_model
      instances = model.selection.select { |e|
        e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      }

      if instances.length == 1
        tr = instances.first.transformation
        x_axis = Geom::Vector3d.new(tr.xaxis).normalize
        y_axis = Geom::Vector3d.new(tr.yaxis).normalize
        z_axis = Geom::Vector3d.new(tr.zaxis).normalize
        {
          'Red Axis (X)'   => x_axis,
          'Green Axis (Y)' => y_axis,
          'Blue Axis (Z)'  => z_axis
        }
      else
        GLOBAL_AXES
      end
    end

    # Rotate the current selection 90 degrees around the given axis vector,
    # pivoting about the selection's bounding-box center.
    def self.rotate_90(axis_vector)
      model = Sketchup.active_model
      selection = model.selection
      return UI.beep if selection.empty?

      bounds = Geom::BoundingBox.new
      selection.each { |e| bounds.add(e.bounds) }
      center = bounds.center
      rotation = Geom::Transformation.rotation(center, axis_vector, 90.degrees)

      model.start_operation('Rotate 90°', true)
      selection.each { |e| e.transform!(rotation) if e.respond_to?(:transform!) }
      model.commit_operation
    end

    # Register the right-click context menu.
    def self.register_context_menu
      UI.add_context_menu_handler do |menu|
        unless Sketchup.active_model.selection.empty?
          sub = menu.add_submenu('Rotate 90°')
          axes_for_selection.each do |label, vector|
            sub.add_item(label) { rotate_90(vector) }
          end
        end
      end
    end
  end
end
