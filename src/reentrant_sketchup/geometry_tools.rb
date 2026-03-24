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

    # Level selected groups/components by removing rotation from their
    # transformations, as if each was set flat on a table.
    def self.level_selection
      model = Sketchup.active_model
      selection = model.selection
      instances = selection.grep(Sketchup::ComponentInstance) +
                  selection.grep(Sketchup::Group)
      return puts('No groups or components selected') if instances.empty?

      model.start_operation('Level Selection', true)
      count = 0
      instances.each do |inst|
        tr = inst.transformation
        # Extract the current scale from each axis column
        x_axis = Geom::Vector3d.new(tr.to_a[0..2])
        y_axis = Geom::Vector3d.new(tr.to_a[4..6])
        z_axis = Geom::Vector3d.new(tr.to_a[8..10])
        sx = x_axis.length
        sy = y_axis.length
        sz = z_axis.length

        # Build a new transformation with the same origin and scale but no rotation
        origin = tr.origin
        new_tr = Geom::Transformation.scaling(origin, sx, sy, sz)
        new_tr = Geom::Transformation.translation(origin.to_a) * Geom::Transformation.scaling(sx, sy, sz)

        inst.transformation = new_tr
        count += 1
      end
      model.commit_operation
      puts "Leveled #{count} instance(s)"
    end

    # Push/pull a selected face so the total extrusion depth equals a target
    # length. SketchUp's native Push/Pull only accepts relative distances;
    # this tool measures the current depth and applies the delta.
    def self.pull_to_length
      model = Sketchup.active_model
      faces = model.selection.grep(Sketchup::Face)
      return UI.messagebox('Select a single face to pull to length.') unless faces.length == 1

      face = faces.first
      normal = face.normal

      # Find the opposing parallel face: same parent, reverse normal, sharing
      # no vertices with the selected face.
      face_verts = face.vertices
      opposite = face.parent.entities.grep(Sketchup::Face).find do |f|
        next if f == face

        f.normal.parallel?(normal) && (f.vertices & face_verts).empty?
      end

      if opposite
        # Current depth is the distance between face planes along the normal.
        current_depth = (face.plane.last - opposite.plane.last).abs
        # Normalise for non-unit normals (plane eq is [a,b,c,d] where
        # a²+b²+c² is already 1 for SketchUp faces, but be safe).
        current_depth /= normal.length if normal.length != 1.0
        formatted = Sketchup.format_length(current_depth)
      else
        current_depth = nil
        formatted = '(no opposite face found)'
      end

      prompts = ['Target length:']
      defaults = [formatted]
      title = 'Pull to Length'
      result = UI.inputbox(prompts, defaults, title)
      return unless result

      target = result[0].to_l
      if current_depth.nil?
        # Without an opposite face, treat the target as a raw pushpull distance.
        delta = target
      else
        delta = target - current_depth
      end

      return puts('Already at target length.') if delta.abs < 0.0001

      model.start_operation('Pull to Length', true)
      # pushpull positive = extrude along face normal, negative = retract.
      face.pushpull(delta)
      model.commit_operation
      puts "Pulled face to #{Sketchup.format_length(target)} (delta: #{Sketchup.format_length(delta)})"
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
