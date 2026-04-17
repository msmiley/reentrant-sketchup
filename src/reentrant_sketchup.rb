# frozen_string_literal: true

require 'sketchup'
require 'extensions'

module ReentrantSketchup
  PLUGIN_NAME = 'Reentrant SketchUp'
  PLUGIN_VERSION = '1.6.1'
  PLUGIN_DIR = File.join(File.dirname(__FILE__), 'reentrant_sketchup')

  extension = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_DIR, 'main'))
  extension.version = PLUGIN_VERSION
  extension.description = 'A collection of frequently used SketchUp operations.'
  extension.creator = 'msmiley'
  extension.copyright = '2026'

  Sketchup.register_extension(extension, true)
end
