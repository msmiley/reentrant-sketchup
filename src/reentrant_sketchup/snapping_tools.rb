# frozen_string_literal: true

module ReentrantSketchup
  module SnappingTools
    @snapping_enabled = true

    # Toggle length and angle snapping on/off.
    # When disabled, both LengthSnap and AngleSnap are turned off so
    # drawing tools move freely without snapping to increments.
    # The previous snap settings are restored when re-enabled.
    def self.toggle_snapping
      model = Sketchup.active_model
      units = model.options['UnitsOptions']

      if @snapping_enabled
        # Save current settings before disabling
        @saved_length_snap = units['LengthSnapEnabled']
        @saved_angle_snap = units['AngleSnapEnabled']
        units['LengthSnapEnabled'] = false
        units['AngleSnapEnabled'] = false
        @snapping_enabled = false
        Sketchup.status_text = 'Snapping disabled'
      else
        # Restore previous settings
        units['LengthSnapEnabled'] = @saved_length_snap.nil? ? true : @saved_length_snap
        units['AngleSnapEnabled'] = @saved_angle_snap.nil? ? true : @saved_angle_snap
        @snapping_enabled = true
        Sketchup.status_text = 'Snapping enabled'
      end
    end

    def self.snapping_enabled?
      @snapping_enabled
    end
  end
end
