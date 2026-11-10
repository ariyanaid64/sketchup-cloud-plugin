require 'sketchup.rb'
require 'extensions.rb'

module SketchupCloud
  module DrawerMakerPro
    PLUGIN_ID = 'drawer_maker_pro'.freeze
    VERSION = '1.0.0'.freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('Drawer Maker Pro', File.join(__dir__, PLUGIN_ID, 'main'))
      ex.description = 'Generate parametric drawers (front, box, bottom, handle) inside cabinet openings, ' \
                       'edit them later and export a cut list.'
      ex.version = VERSION
      ex.creator = 'sketchup-cloud-plugin'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
