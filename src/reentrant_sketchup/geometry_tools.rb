# frozen_string_literal: true

module ReentrantSketchup
  module GeometryTools
    # Calculate the total area of all selected faces.
    def self.total_face_area
      model = Sketchup.active_model
      faces = model.selection.grep(Sketchup::Face)
      return puts('No faces selected') if faces.empty?

      total = faces.sum(&:area)
      unit_helper = Sketchup.format_area(total)
      puts "Total area of #{faces.length} faces: #{unit_helper}"
      total
    end

    # Calculate the total length of all selected edges.
    def self.total_edge_length
      model = Sketchup.active_model
      edges = model.selection.grep(Sketchup::Edge)
      return puts('No edges selected') if edges.empty?

      total = edges.sum(&:length)
      formatted = Sketchup.format_length(total)
      puts "Total length of #{edges.length} edges: #{formatted}"
      total
    end

    # Report the bounding box dimensions of the current selection.
    def self.selection_bounds
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      bounds = Geom::BoundingBox.new
      selection.each { |e| bounds.add(e.bounds) if e.respond_to?(:bounds) }

      width = Sketchup.format_length(bounds.width)
      height = Sketchup.format_length(bounds.height)
      depth = Sketchup.format_length(bounds.depth)
      puts "Selection bounds: #{width} x #{depth} x #{height} (W x D x H)"
      bounds
    end

    # Move selected entities by the given vector [x, y, z] (in inches).
    def self.move_selection(x, y, z)
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      vector = Geom::Vector3d.new(x, y, z)
      transform = Geom::Transformation.translation(vector)
      model.active_entities.transform_entities(transform, selection.to_a)
      puts "Moved #{selection.count} entities by [#{x}, #{y}, #{z}]"
    end

    # Scale selected entities uniformly by the given factor.
    def self.scale_selection(factor)
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      bounds = Geom::BoundingBox.new
      selection.each { |e| bounds.add(e.bounds) if e.respond_to?(:bounds) }
      center = bounds.center

      transform = Geom::Transformation.scaling(center, factor)
      model.active_entities.transform_entities(transform, selection.to_a)
      puts "Scaled #{selection.count} entities by factor #{factor}"
    end

    # Reverse faces so normals point outward (away from origin of bounding box).
    def self.orient_faces
      model = Sketchup.active_model
      faces = model.selection.grep(Sketchup::Face)
      return puts('No faces selected') if faces.empty?

      count = 0
      model.start_operation('Orient Faces', true)
      faces.each do |face|
        center = face.bounds.center
        if face.normal.dot(center.to_a.map { |c| c <=> 0 }) < 0
          face.reverse!
          count += 1
        end
      end
      model.commit_operation
      puts "Reversed #{count} of #{faces.length} faces"
    end
  end
end
