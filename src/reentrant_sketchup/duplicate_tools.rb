# frozen_string_literal: true

module ReentrantSketchup
  module DuplicateTools
    # Duplicate the selected entities in place. Groups and component instances
    # are duplicated by inserting a new instance with the same definition and
    # transformation. Loose geometry (edges, faces, etc.) is copied via a
    # temporary group round-trip.
    def self.duplicate_in_place
      model = Sketchup.active_model
      selection = model.selection
      return UI.beep if selection.empty?

      entities = model.active_entities
      originals = selection.to_a

      model.start_operation('Duplicate in Place', true)

      copies = []
      containers = []
      loose = []

      originals.each do |e|
        if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          containers << e
        else
          loose << e
        end
      end

      # Duplicate groups and component instances via their definition
      containers.each do |e|
        copy = entities.add_instance(e.definition, e.transformation)
        # Preserve material and layer assignments
        copy.material = e.material if e.material
        copy.layer = e.layer if e.respond_to?(:layer)
        copies << copy
      end

      # Duplicate loose geometry by grouping, copying, and exploding
      unless loose.empty?
        temp_group = entities.add_group(loose)
        copy_group = entities.add_instance(temp_group.definition, temp_group.transformation)
        # Explode both to restore loose geometry
        temp_group.explode
        new_ents = copy_group.explode
        copies.concat(new_ents.compact)
      end

      model.commit_operation

      # Select the new copies
      model.selection.clear
      model.selection.add(copies)
      puts "Duplicated #{originals.length} entities in place"
    end

    # Register the right-click context menu item.
    def self.register_context_menu
      UI.add_context_menu_handler do |menu|
        unless Sketchup.active_model.selection.empty?
          menu.add_item('Duplicate') { duplicate_in_place }
        end
      end
    end
  end
end
