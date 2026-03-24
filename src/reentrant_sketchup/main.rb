# frozen_string_literal: true

require_relative 'selection_tools'
require_relative 'geometry_tools'
require_relative 'group_tools'
require_relative 'layer_tools'
require_relative 'material_tools'
require_relative 'camera_tools'
require_relative 'menu'

module ReentrantSketchup
  Sketchup.status_text = "#{PLUGIN_NAME} v#{PLUGIN_VERSION} loaded"
end
