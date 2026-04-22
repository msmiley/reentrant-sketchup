# frozen_string_literal: true

module ReentrantSketchup
  module AlignTools
    GLOBAL_AXES = {
      'Red Axis (X)'   => Geom::Vector3d.new(1, 0, 0),
      'Green Axis (Y)' => Geom::Vector3d.new(0, 1, 0),
      'Blue Axis (Z)'  => Geom::Vector3d.new(0, 0, 1)
    }.freeze

    # Return the alignment axes based on the first selected entity.
    # If it's a component instance or group, use its local axes.
    def self.axes_for_reference
      model = Sketchup.active_model
      ref = model.selection.first

      if ref.is_a?(Sketchup::ComponentInstance) || ref.is_a?(Sketchup::Group)
        tr = ref.transformation
        {
          'Red Axis (X)'   => tr.xaxis.normalize,
          'Green Axis (Y)' => tr.yaxis.normalize,
          'Blue Axis (Z)'  => tr.zaxis.normalize
        }
      else
        GLOBAL_AXES
      end
    end

    # Align all selected entities to the first selected entity along the
    # given axis vector. Projects each entity's bounding-box center onto
    # the axis and moves it to match the reference.
    def self.align_to_first(axis_vector)
      model = Sketchup.active_model
      selection = model.selection.to_a
      return UI.beep if selection.length < 2

      ref_center = selection.first.bounds.center
      axis = axis_vector.normalize

      model.start_operation('Align', true)
      selection[1..].each do |entity|
        next unless entity.respond_to?(:transform!)

        current_center = entity.bounds.center
        diff = ref_center - current_center
        # Project the difference onto the axis — move only along that direction
        offset = axis.clone
        offset.length = diff % axis
        entity.transform!(Geom::Transformation.translation(offset))
      end
      model.commit_operation
    end

    # Register the right-click context menu.
    def self.register_context_menu
      UI.add_context_menu_handler do |menu|
        if Sketchup.active_model.selection.length >= 2
          sub = menu.add_submenu('Align')
          axes_for_reference.each do |label, vector|
            sub.add_item(label) { align_to_first(vector) }
          end
        end
      end
    end
  end
end
