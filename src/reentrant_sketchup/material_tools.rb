# frozen_string_literal: true

module ReentrantSketchup
  module MaterialTools
    # Apply a material by name to all selected entities.
    def self.apply_material(material_name)
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      material = model.materials[material_name]
      return puts("Material '#{material_name}' not found") unless material

      model.start_operation('Apply Material', true)
      selection.each { |e| e.material = material if e.respond_to?(:material=) }
      model.commit_operation
      puts "Applied '#{material_name}' to #{selection.count} entities"
    end

    # Create a new material with the given RGB color (0-255).
    def self.create_color_material(name, r, g, b, alpha = 255)
      model = Sketchup.active_model
      material = model.materials.add(name)
      material.color = Sketchup::Color.new(r, g, b, alpha)
      puts "Created material '#{name}' [#{r}, #{g}, #{b}, #{alpha}]"
      material
    end

    # Remove all unused materials from the model.
    def self.purge_unused_materials
      model = Sketchup.active_model
      unused = model.materials.select { |m| !m.used? }
      return puts('No unused materials found') if unused.empty?

      unused.each { |m| model.materials.remove(m) }
      puts "Purged #{unused.length} unused materials"
    end

    # List all materials and their usage status.
    def self.list_materials
      model = Sketchup.active_model
      model.materials.each do |mat|
        used = mat.used? ? 'used' : 'unused'
        color = mat.color
        puts "#{mat.name}: [#{color.red}, #{color.green}, #{color.blue}] (#{used})"
      end
    end

    # Select all faces that use the given material name.
    def self.select_by_material(material_name)
      model = Sketchup.active_model
      material = model.materials[material_name]
      return puts("Material '#{material_name}' not found") unless material

      faces = model.active_entities.grep(Sketchup::Face).select do |f|
        f.material == material || f.back_material == material
      end

      model.selection.clear
      model.selection.add(faces)
      puts "Selected #{faces.length} faces with material '#{material_name}'"
    end
  end
end
