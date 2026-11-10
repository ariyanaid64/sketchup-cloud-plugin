require 'sketchup.rb'
require_relative 'calculator'
require_relative 'builder'
require_relative 'cabinet_calculator'
require_relative 'cabinet_builder'
require_relative 'space_tool'
require_relative 'cutlist'
require_relative 'dialog'
require_relative 'motion'

module SketchupCloud
  module DrawerMakerPro
    module_function

    def selected_set
      sel = Sketchup.active_model.selection.to_a
      sel.first if sel.length == 1 && (Builder.drawer_set?(sel.first) || CabinetBuilder.cabinet_set?(sel.first))
    end

    def insert_drawers
      model = Sketchup.active_model
      sel = model.selection.to_a
      if sel.size == 1 && CabinetBuilder.cabinet_set?(sel.first)
        insert_into_bay(sel.first)
      elsif sel.size == 1 && Builder.drawer_set?(sel.first)
        Dialog.open(set: sel.first)
      elsif sel.size == 1 && container?(sel.first)
        from_container(model, sel.first)
      else
        pick_space
      end
    end

    def container?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def from_container(model, inst)
      bb = inst.definition.bounds
      space = { 'width' => bb.width.to_mm.round(1), 'depth' => bb.height.to_mm.round(1),
                'height' => bb.depth.to_mm.round(1) }
      Dialog.open(entities: model.active_entities,
                  transformation: inst.transformation * Geom::Transformation.translation(bb.min), space: space)
    end

    def create_cabinet
      model = Sketchup.active_model
      Dialog.open(kind: 'cabinet', entities: model.active_entities,
                  transformation: Geom::Transformation.new,
                  space: { 'width' => 900.0, 'depth' => 560.0, 'height' => 800.0 })
    end

    def insert_into_bay(set)
      openings = JSON.parse(set.get_attribute(Builder::DICT, 'openings', '[]'))
      raise ArgumentError, 'Kabinet tidak memiliki ruang kosong.' if openings.empty?
      options = openings.map { |opening| opening.fetch('name') }
      input = UI.inputbox(['Ruang kabinet'], [options.first], [options.join('|')], 'Insert Drawers · Pilih ruang')
      return unless input
      opening = openings.find { |entry| entry['name'] == input.first }
      return unless opening
      # Inserts remain independent so changing a cabinet cannot erase its drawers.
      transform = set.transformation * Geom::Transformation.translation(opening.fetch('origin').map(&:mm))
      Dialog.open(entities: Sketchup.active_model.active_entities, transformation: transform, space: opening.fetch('space'))
    end

    def pick_space
      Sketchup.active_model.select_tool(SpaceTool.new do |entities, tr, space|
        Dialog.open(entities: entities, transformation: tr, space: space)
      end)
    end

    def edit_selected
      set = selected_set
      unless set
        UI.messagebox('Pilih satu set laci atau Smart Box untuk diedit.')
        return
      end
      Dialog.open(set: set, kind: CabinetBuilder.cabinet_set?(set) ? 'cabinet' : 'drawer')
    end

    def toggle_selected
      set = selected_set
      raise ArgumentError, 'Pilih satu set laci atau Smart Box terlebih dahulu.' unless set
      Motion.toggle(set)
    end

    def command(label, icon, description, &action)
      cmd = UI::Command.new(label) do
        begin
          action.call
        rescue StandardError => e
          UI.messagebox("Drawer Maker Pro: #{e.message}")
        end
      end
      cmd.tooltip = label
      cmd.status_bar_text = description
      dir = File.join(__dir__, 'icons')
      if Sketchup.platform == :platform_win
        cmd.small_icon = cmd.large_icon = File.join(dir, "#{icon}.svg")
      else
        cmd.small_icon = File.join(dir, "#{icon}_16.png")
        cmd.large_icon = File.join(dir, "#{icon}_24.png")
      end
      cmd
    end

    unless file_loaded?(__FILE__)
      cabinet = command('Smart Box · New Cabinet', 'cabinet', 'Buat kabinet, sekat, rak, dan pintu di origin konteks aktif.') { create_cabinet }
      insert = command('Insert Drawers', 'drawer', 'Pilih Smart Box untuk memilih ruang, atau pilih kotak ruang / set laci.') { insert_drawers }
      pick = command('Space Tool', 'space', 'Pilih dua sudut diagonal bagian dalam bukaan.') { pick_space }
      edit = command('Edit / Replace Style', 'edit', 'Ubah parameter, tipe laci, atau gaya pintu pada set terpilih.') { edit_selected }
      motion = command('Open / Close', 'motion', 'Buka atau tutup semua pintu / laci pada set terpilih.') { toggle_selected }
      cut = command('Export Cut List...', 'cutlist', 'Ekspor daftar part generik ke CSV.') { CutList.export }
      @commands = [cabinet, insert, pick, edit, motion, cut]
      menu = UI.menu('Extensions').add_submenu('Drawer Maker Pro')
      @commands.each { |cmd| menu.add_item(cmd) }
      UI.add_context_menu_handler do |ctx|
        set = selected_set
        if set
          ctx.add_item(edit)
          ctx.add_item(motion)
          ctx.add_item(insert) if CabinetBuilder.cabinet_set?(set)
        elsif Sketchup.active_model.selection.size == 1 && container?(Sketchup.active_model.selection.first)
          ctx.add_item(insert)
        end
      end
      @toolbar = UI::Toolbar.new('Drawer Maker Pro')
      @commands.each { |cmd| @toolbar.add_item(cmd) }
      @toolbar.restore
      file_loaded(__FILE__)
    end
  end
end
