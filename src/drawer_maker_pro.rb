require 'sketchup.rb'
require 'extensions.rb'

module SketchupCloud
  module DrawerMakerPro
    PLUGIN_ID = 'drawer_maker_pro'.freeze
    VERSION = '1.1.0'.freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('Drawer Maker Pro', File.join(__dir__, PLUGIN_ID, 'main'))
      ex.description = 'Parametric drawer styles and Smart Box cabinets with shelves, framed/glass doors, ' \
                       'open/close, editable presets and a cut list.'
      ex.version = VERSION
      ex.creator = 'sketchup-cloud-plugin'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
