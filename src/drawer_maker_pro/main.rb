require 'sketchup.rb'
require_relative 'calculator'
require_relative 'builder'
require_relative 'space_tool'
require_relative 'cutlist'
require_relative 'dialog'

module SketchupCloud
  module DrawerMakerPro
    module_function

    # Selected drawer set -> edit it. Selected group/component -> use its
    # bounds as the space. Otherwise start the Space Tool.
    def insert_drawers
      model = Sketchup.active_model
      sel = model.selection.to_a
      if sel.size == 1 && Builder.drawer_set?(sel[0])
        Dialog.new(set: sel[0]).show
      elsif sel.size == 1 && (sel[0].is_a?(Sketchup::Group) || sel[0].is_a?(Sketchup::ComponentInstance))
        from_container(model, sel[0])
      else
        pick_space
      end
    end

    def from_container(model, inst)
      bb = inst.definition.bounds
      space = { 'width' => bb.width.to_mm.round(1), 'depth' => bb.height.to_mm.round(1),
                'height' => bb.depth.to_mm.round(1) }
      tr = inst.transformation * Geom::Transformation.translation(bb.min)
      parent = inst.parent.respond_to?(:entities) ? inst.parent.entities : model.active_entities
      Dialog.new(entities: parent, transformation: tr, space: space).show
    end

    def pick_space
      Sketchup.active_model.select_tool(SpaceTool.new do |entities, tr, space|
        Dialog.new(entities: entities, transformation: tr, space: space).show
      end)
    end

    def edit_selected
      sel = Sketchup.active_model.selection.to_a
      if sel.size == 1 && Builder.drawer_set?(sel[0])
        Dialog.new(set: sel[0]).show
      else
        UI.messagebox('Select one drawer set to edit.')
      end
    end

    # SVG on Windows; macOS SketchUp does not load SVG toolbar icons, so use PNG there.
    def set_icons(cmd, name)
      dir = File.join(__dir__, 'icons')
      if Sketchup.platform == :platform_win
        cmd.small_icon = cmd.large_icon = File.join(dir, "#{name}.svg")
      else
        cmd.small_icon = File.join(dir, "#{name}_16.png")
        cmd.large_icon = File.join(dir, "#{name}_24.png")
      end
    end

    unless file_loaded?(__FILE__)
      cmd_insert = UI::Command.new('Insert Drawers') { insert_drawers }
      cmd_insert.tooltip = 'Insert Drawers'
      cmd_insert.status_bar_text = 'Pick an opening (or select a space box / drawer set) and generate drawers.'
      set_icons(cmd_insert, 'drawer')

      cmd_pick = UI::Command.new('Space Tool') { pick_space }
      cmd_pick.tooltip = 'Space Tool'
      cmd_pick.status_bar_text = 'Pick two diagonal inner corners of an opening.'
      set_icons(cmd_pick, 'space')

      cmd_edit = UI::Command.new('Edit Drawer Set') { edit_selected }
      set_icons(cmd_edit, 'edit')
      cmd_edit.tooltip = 'Edit Drawer Set'

      cmd_cut = UI::Command.new('Export Cut List...') { CutList.export }
      set_icons(cmd_cut, 'cutlist')
      cmd_cut.tooltip = 'Export Cut List (CSV)'

      menu = UI.menu('Extensions').add_submenu('Drawer Maker Pro')
      [cmd_insert, cmd_pick, cmd_edit].each { |c| menu.add_item(c) }
      menu.add_separator
      menu.add_item(cmd_cut)

      UI.add_context_menu_handler do |ctx|
        sel = Sketchup.active_model.selection.to_a
        if sel.size == 1 && Builder.drawer_set?(sel[0])
          ctx.add_item(cmd_edit)
        elsif sel.size == 1 && (sel[0].is_a?(Sketchup::Group) || sel[0].is_a?(Sketchup::ComponentInstance))
          ctx.add_item(cmd_insert)
        end
      end

      tb = UI::Toolbar.new('Drawer Maker Pro')
      [cmd_insert, cmd_pick, cmd_edit, cmd_cut].each { |c| tb.add_item(c) }
      tb.restore

      file_loaded(__FILE__)
    end
  end
end
