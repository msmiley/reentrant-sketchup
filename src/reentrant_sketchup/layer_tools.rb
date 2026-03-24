# frozen_string_literal: true

module ReentrantSketchup
  module LayerTools
    # Move all selected entities to a named layer/tag, creating it if needed.
    def self.move_to_layer(layer_name)
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      model.start_operation('Move to Layer', true)
      layer = model.layers[layer_name] || model.layers.add(layer_name)
      selection.each { |e| e.layer = layer if e.respond_to?(:layer=) }
      model.commit_operation
      puts "Moved #{selection.count} entities to layer '#{layer_name}'"
    end

    # Select all entities on the named layer/tag.
    def self.select_by_layer(layer_name)
      model = Sketchup.active_model
      layer = model.layers[layer_name]
      return puts("Layer '#{layer_name}' not found") unless layer

      matches = model.active_entities.select { |e| e.respond_to?(:layer) && e.layer == layer }
      model.selection.clear
      model.selection.add(matches)
      puts "Selected #{matches.length} entities on layer '#{layer_name}'"
    end

    # Toggle visibility of the named layer/tag.
    def self.toggle_layer(layer_name)
      model = Sketchup.active_model
      layer = model.layers[layer_name]
      return puts("Layer '#{layer_name}' not found") unless layer

      layer.visible = !layer.visible?
      state = layer.visible? ? 'visible' : 'hidden'
      puts "Layer '#{layer_name}' is now #{state}"
    end

    # Hide all layers/tags except the one specified.
    def self.isolate_layer(layer_name)
      model = Sketchup.active_model
      target = model.layers[layer_name]
      return puts("Layer '#{layer_name}' not found") unless target

      model.start_operation('Isolate Layer', true)
      model.layers.each { |l| l.visible = (l == target) }
      model.commit_operation
      puts "Isolated layer '#{layer_name}'"
    end

    # Show all layers/tags.
    def self.show_all_layers
      model = Sketchup.active_model
      model.start_operation('Show All Layers', true)
      model.layers.each { |l| l.visible = true }
      model.commit_operation
      puts "All #{model.layers.count} layers are now visible"
    end

    # List all layers/tags and their entity counts.
    def self.list_layers
      model = Sketchup.active_model
      model.layers.each do |layer|
        count = model.active_entities.count { |e| e.respond_to?(:layer) && e.layer == layer }
        vis = layer.visible? ? '+' : '-'
        puts "[#{vis}] #{layer.name}: #{count} entities"
      end
    end
  end
end
