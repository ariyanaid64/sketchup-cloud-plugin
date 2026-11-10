require 'json'

module SketchupCloud
  module DrawerMakerPro
    # HtmlDialog with the drawer parameters (mirrors the "Drawer" panel:
    # insert face, accessories, size parameters, Create).
    class Dialog
      PREF_KEY = 'SketchupCloud_DrawerMakerPro'.freeze

      def self.last_params
        raw = Sketchup.read_default(PREF_KEY, 'params', nil)
        raw ? JSON.parse(raw) : {}
      rescue JSON::ParserError
        {}
      end

      # target: { entities:, transformation:, space: } for a new set,
      # or { set: Group } to edit an existing one.
      def initialize(target)
        @target = target
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'Drawer Maker Pro',
          preferences_key: PREF_KEY,
          scrollable: true, resizable: true,
          width: 400, height: 720, min_width: 340, min_height: 480,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(__dir__, 'html', 'dialog.html'))
        @dialog.add_action_callback('ready') { |_ctx| push_state }
        @dialog.add_action_callback('create') { |_ctx, json| on_create(json) }
        @dialog.add_action_callback('cancel') { |_ctx| @dialog.close }
      end

      def show
        @dialog.show
      end

      private

      def edit?
        @target.key?(:set)
      end

      def space
        edit? ? JSON.parse(@target[:set].get_attribute(Builder::DICT, 'space')) : @target[:space]
      end

      def params
        stored = edit? ? @target[:set].get_attribute(Builder::DICT, 'params') : nil
        Calculator.normalize(stored ? JSON.parse(stored) : self.class.last_params)
      end

      def push_state
        state = { mode: edit? ? 'edit' : 'create', space: space, params: params }
        @dialog.execute_script("DMP.load(#{JSON.generate(state)})")
      end

      def on_create(json)
        p = JSON.parse(json)
        Calculator.compute(space, p) # validate before touching the model
        if edit? && @target[:set].valid?
          Builder.rebuild(@target[:set], p)
        else
          set = Builder.create(@target[:entities], @target[:transformation], space, p)
          Sketchup.active_model.selection.clear
          Sketchup.active_model.selection.add(set)
        end
        Sketchup.write_default(PREF_KEY, 'params', JSON.generate(p))
        @dialog.close
      rescue ArgumentError, JSON::ParserError => e
        @dialog.execute_script("DMP.error(#{JSON.generate(e.message)})")
      end
    end
  end
end
