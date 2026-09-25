# frozen_string_literal: true

module ReentrantSketchup
  module GroupTools
    # Wrap the current selection in a new group.
    def self.group_selection
      model = Sketchup.active_model
      selection = model.selection
      return puts('Nothing selected') if selection.empty?

      model.start_operation('Group Selection', true)
      group = model.active_entities.add_group(selection.to_a)
      model.commit_operation

      model.selection.clear
      model.selection.add(group)
      puts "Created group from #{selection.count} entities"
      group
    end

    # Explode all selected groups and component instances one level.
    def self.explode_selection
      model = Sketchup.active_model
      selection = model.selection.to_a
      containers = selection.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      return puts('No groups or components selected') if containers.empty?

      model.start_operation('Explode Selection', true)
      new_entities = []
      containers.each { |c| new_entities.concat(c.explode) }
      model.commit_operation

      model.selection.clear
      model.selection.add(new_entities.compact)
      puts "Exploded #{containers.length} containers"
    end

    # Convert a selected group to a component definition.
    def self.group_to_component
      model = Sketchup.active_model
      groups = model.selection.grep(Sketchup::Group)
      return puts('No groups selected') if groups.empty?

      model.start_operation('Group to Component', true)
      groups.each do |group|
        group.to_component
      end
      model.commit_operation
      puts "Converted #{groups.length} groups to components"
    end

    # Lock all selected groups and component instances.
    def self.lock_selection
      model = Sketchup.active_model
      lockable = model.selection.select { |e| e.respond_to?(:locked=) }
      return puts('No lockable entities selected') if lockable.empty?

      model.start_operation('Lock Selection', true)
      lockable.each { |e| e.locked = true }
      model.commit_operation
      puts "Locked #{lockable.length} entities"
    end

    # Unlock all selected groups and component instances.
    def self.unlock_selection
      model = Sketchup.active_model
      lockable = model.selection.select { |e| e.respond_to?(:locked=) }
      return puts('No lockable entities selected') if lockable.empty?

      model.start_operation('Unlock Selection', true)
      lockable.each { |e| e.locked = false }
      model.commit_operation
      puts "Unlocked #{lockable.length} entities"
    end

    # Make each selected component instance unique independently.
    # Unlike the native Make Unique which gives all selected instances a single
    # new shared definition, this creates a separate unique definition for each.
    def self.make_unique_each
      model = Sketchup.active_model
      components = model.selection.grep(Sketchup::ComponentInstance)
      return puts('No component instances selected') if components.empty?

      model.start_operation('Make Unique Each', true)
      components.each(&:make_unique)
      model.commit_operation
      puts "Made #{components.length} components independently unique"
    end

    # A group or component instance counts as a solid when every edge in its
    # definition is bounded by exactly two faces. Group#manifold? is deprecated
    # (it checks the definition, not the instance) and ComponentInstance has no
    # #manifold? at all, so go through the definition — using
    # ComponentDefinition#manifold? where the running SketchUp offers it and
    # falling back to the edge test where it does not.
    def self.solid?(entity)
      return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      return false unless entity.valid? && entity.respond_to?(:definition)

      definition = entity.definition
      return false if definition.nil?
      return definition.manifold? if definition.respond_to?(:manifold?)

      entities = definition.entities
      return false if entities.grep(Sketchup::Face).empty?

      entities.grep(Sketchup::Edge).all? { |edge| edge.faces.length == 2 }
    end

    # Human-readable label for a group or instance, for console messages.
    def self.display_name(entity)
      name = entity.name.to_s
      return name unless name.empty?
      return entity.definition.name if entity.respond_to?(:definition)

      entity.to_s
    end

    # Trim the selected solids with a cutter picked afterwards. Selection order
    # is not reliable in SketchUp (window selections and re-clicks reorder it),
    # so instead of treating the "first" selected solid as the cutter, select
    # the targets, run the command, then click the cutter in the viewport.
    # Requires SketchUp Pro (Solid Tools).
    def self.trim_multiple
      model = Sketchup.active_model
      unless Sketchup.is_pro?
        return puts('Trim Multiple needs SketchUp Pro (Solid Tools)')
      end

      targets = model.selection.select { |e| solid?(e) }
      return puts('Select the solid groups/components to trim first') if targets.empty?

      model.select_tool(TrimCutterTool.new(targets))
    end

    # Remove the volume of `cutter` from every solid in `targets`. The cutter
    # is preserved.
    #
    # The Solid Tools API reads backwards here: `a.trim(b)` trims *b*, erases
    # the original b, and returns a brand new group holding the trimmed result;
    # `a` — the cutting solid — is left untouched. So the cutter has to be the
    # receiver and each target the argument. Failure is reported by a nil
    # return value rather than an exception.
    def self.trim_with(cutter, targets)
      model = Sketchup.active_model
      targets = targets.reject { |t| t == cutter }
      return puts('Nothing to trim') if targets.empty?

      cutter_name = display_name(cutter)

      model.start_operation('Trim Multiple', true)
      results = []
      failed = 0
      targets.each do |target|
        unless cutter.valid?
          puts "Cutter '#{cutter_name}' was consumed — stopping"
          break
        end
        next unless target.valid?

        target_name = display_name(target)
        begin
          # Returns the new trimmed group, or nil if the pair is not trimmable.
          result = cutter.trim(target)
          if result
            results << result
          else
            failed += 1
            puts "Trim failed on '#{target_name}' (no intersection, or not a solid)"
          end
        rescue StandardError => e
          failed += 1
          puts "Skipping '#{target_name}': #{e.class}: #{e.message}"
        end
      end

      if results.empty?
        model.abort_operation
        return puts("Nothing trimmed with '#{cutter_name}' (#{failed} failed)")
      end

      model.commit_operation

      model.selection.clear
      model.selection.add(([cutter] + results).select(&:valid?))
      suffix = failed.zero? ? '' : " (#{failed} failed)"
      puts "Trimmed #{results.length} solids with '#{cutter_name}'#{suffix}"
      results
    end

    # Interactive step of Trim Multiple: highlights the solid under the cursor
    # and trims the stored targets with whichever solid is clicked.
    class TrimCutterTool
      PROMPT = 'Trim Multiple: click the cutter solid (Esc to cancel)'

      def initialize(targets)
        @targets = targets
        @hover = nil
      end

      def activate
        Sketchup.status_text = "#{PROMPT} — #{@targets.length} target(s) selected"
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(_reason, _view)
        puts 'Trim Multiple cancelled'
        Sketchup.active_model.select_tool(nil)
      end

      def onMouseMove(_flags, x, y, view)
        hover = pick_solid(view, x, y)
        return if hover == @hover

        @hover = hover
        Sketchup.status_text = hover ? "Cutter: #{GroupTools.display_name(hover)}" : PROMPT
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        cutter = pick_solid(view, x, y)
        unless cutter
          Sketchup.status_text = "Not a solid — #{PROMPT}"
          return
        end

        @targets.select!(&:valid?)
        Sketchup.active_model.select_tool(nil)
        GroupTools.trim_with(cutter, @targets)
      end

      def draw(view)
        return unless @hover&.valid?

        bb = @hover.bounds
        tr = Sketchup.active_model.edit_transform
        pts = (0..7).map { |i| bb.corner(i).transform(tr) }
        view.drawing_color = 'red'
        view.line_width = 3
        # Corner indices: bit 0 = x, bit 1 = y, bit 2 = z.
        edges = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3],
                 [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
        view.draw(GL_LINES, edges.flatten.map { |i| pts[i] })
      end

      private

      def pick_solid(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked
        GroupTools.solid?(entity) ? entity : nil
      end
    end

    # Remove all empty groups and component instances from the model.
    def self.purge_empty_groups
      model = Sketchup.active_model
      entities = model.active_entities

      empty = entities.select do |e|
        (e.is_a?(Sketchup::Group) && e.entities.length == 0) ||
          (e.is_a?(Sketchup::ComponentInstance) && e.definition.entities.length == 0)
      end

      return puts('No empty groups/components found') if empty.empty?

      model.start_operation('Purge Empty Groups', true)
      entities.erase_entities(empty)
      model.commit_operation
      puts "Purged #{empty.length} empty groups/components"
    end
  end
end
