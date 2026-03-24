# frozen_string_literal: true

module ReentrantSketchup
  module SelectionTools
    # Select all edges in the current context.
    def self.select_all_edges
      model = Sketchup.active_model
      entities = model.active_entities
      edges = entities.grep(Sketchup::Edge)
      model.selection.clear
      model.selection.add(edges)
      puts "Selected #{edges.length} edges"
    end

    # Select all faces in the current context.
    def self.select_all_faces
      model = Sketchup.active_model
      entities = model.active_entities
      faces = entities.grep(Sketchup::Face)
      model.selection.clear
      model.selection.add(faces)
      puts "Selected #{faces.length} faces"
    end

    # Select all groups in the current context.
    def self.select_all_groups
      model = Sketchup.active_model
      entities = model.active_entities
      groups = entities.grep(Sketchup::Group)
      model.selection.clear
      model.selection.add(groups)
      puts "Selected #{groups.length} groups"
    end

    # Select all component instances in the current context.
    def self.select_all_components
      model = Sketchup.active_model
      entities = model.active_entities
      components = entities.grep(Sketchup::ComponentInstance)
      model.selection.clear
      model.selection.add(components)
      puts "Selected #{components.length} component instances"
    end

    # Select all entities connected to the current selection.
    def self.select_connected
      model = Sketchup.active_model
      selection = model.selection
      return if selection.empty?

      connected = Set.new(selection.to_a)
      queue = selection.to_a.dup

      until queue.empty?
        entity = queue.shift
        neighbors = []

        case entity
        when Sketchup::Edge
          neighbors.concat(entity.faces)
          neighbors.concat(entity.start.edges)
          neighbors.concat(entity.end.edges)
        when Sketchup::Face
          neighbors.concat(entity.edges)
        end

        neighbors.each do |neighbor|
          unless connected.include?(neighbor)
            connected.add(neighbor)
            queue.push(neighbor)
          end
        end
      end

      selection.clear
      selection.add(connected.to_a)
      puts "Selected #{connected.size} connected entities"
    end

    # Invert the current selection within the active context.
    def self.invert_selection
      model = Sketchup.active_model
      all = model.active_entities.to_a
      selected = model.selection.to_a
      inverted = all - selected
      model.selection.clear
      model.selection.add(inverted)
      puts "Inverted selection: #{inverted.length} entities"
    end
  end
end
