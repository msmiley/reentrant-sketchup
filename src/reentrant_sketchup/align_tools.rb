# frozen_string_literal: true

module ReentrantSketchup
  module AlignTools
    AXES = {
      'Red Axis (X)'   => 0,
      'Green Axis (Y)' => 1,
      'Blue Axis (Z)'  => 2
    }.freeze

    # Align all selected entities to the first selected entity along the
    # given axis index (0=X, 1=Y, 2=Z). Each entity's bounding-box center
    # is moved to match the reference's center on that axis.
    def self.align_to_first(axis_index)
      model = Sketchup.active_model
      selection = model.selection.to_a
      return UI.beep if selection.length < 2

      ref_center = selection.first.bounds.center
      target = ref_center.to_a[axis_index]

      model.start_operation('Align', true)
      selection[1..].each do |entity|
        next unless entity.respond_to?(:transform!)

        current = entity.bounds.center.to_a[axis_index]
        delta = [0, 0, 0]
        delta[axis_index] = target - current
        entity.transform!(Geom::Transformation.translation(delta))
      end
      model.commit_operation
      axis_name = %w[X Y Z][axis_index]
      puts "Aligned #{selection.length - 1} entities to first on #{axis_name} axis"
    end

    # Register the right-click context menu.
    def self.register_context_menu
      UI.add_context_menu_handler do |menu|
        if Sketchup.active_model.selection.length >= 2
          sub = menu.add_submenu('Align')
          AXES.each do |label, index|
            sub.add_item(label) { align_to_first(index) }
          end
        end
      end
    end
  end
end
