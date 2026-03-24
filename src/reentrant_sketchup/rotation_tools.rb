# frozen_string_literal: true

module ReentrantSketchup
  module RotationTools
    AXES = {
      'Red Axis (X)'   => Geom::Vector3d.new(1, 0, 0),
      'Green Axis (Y)' => Geom::Vector3d.new(0, 1, 0),
      'Blue Axis (Z)'  => Geom::Vector3d.new(0, 0, 1)
    }.freeze

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
          AXES.each do |label, vector|
            sub.add_item(label) { rotate_90(vector) }
          end
        end
      end
    end
  end
end
