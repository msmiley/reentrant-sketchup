# frozen_string_literal: true

require_relative 'selection_tools'
require_relative 'geometry_tools'
require_relative 'group_tools'
require_relative 'layer_tools'
require_relative 'material_tools'
require_relative 'camera_tools'
require_relative 'rotation_tools'
require_relative 'updater'
require_relative 'menu'

module ReentrantSketchup
  Sketchup.status_text = "#{PLUGIN_NAME} v#{PLUGIN_VERSION} loaded"

  # Defer update check until SketchUp is fully initialized
  UI.start_timer(5.0, false) { Updater.check_for_update(notify_if_current: false) }
end
