# frozen_string_literal: true

module ReentrantSketchup
  module SnappingTools
    # Toggle length and angle snapping on/off.
    # Reads current state directly from the model options so the toggle
    # always reflects the actual SketchUp setting.
    def self.toggle_snapping
      model = Sketchup.active_model
      units = model.options['UnitsOptions']

      # Treat snapping as "on" if either length or angle snap is enabled
      currently_on = units['LengthSnapEnabled'] || units['AngleSnapEnabled']

      if currently_on
        units['LengthSnapEnabled'] = false
        units['AngleSnapEnabled'] = false
        Sketchup.status_text = 'Snapping disabled'
      else
        units['LengthSnapEnabled'] = true
        units['AngleSnapEnabled'] = true
        Sketchup.status_text = 'Snapping enabled'
      end
    end

    def self.snapping_enabled?
      model = Sketchup.active_model
      return true unless model

      units = model.options['UnitsOptions']
      units['LengthSnapEnabled'] || units['AngleSnapEnabled']
    end
  end
end
