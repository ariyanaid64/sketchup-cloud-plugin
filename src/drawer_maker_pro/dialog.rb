require 'json'

module SketchupCloud
  module DrawerMakerPro
    class Dialog
      PREF_KEY = 'SketchupCloud_DrawerMakerPro'.freeze
      @instances = []

      def self.open(target)
        instance = new(target)
        @instances << instance
        instance.show { @instances.delete(instance) }
        instance
      end

      def initialize(target)
        @target = target
        @model = Sketchup.active_model
        @edit_path = @model.active_path
        @kind = target[:kind] || 'drawer'
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'Drawer Maker Pro · Workshop', preferences_key: "#{PREF_KEY}_#{@kind}",
          scrollable: true, resizable: true, width: 480, height: 820,
          min_width: 360, min_height: 520, style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(__dir__, 'html', 'dialog.html'))
        @dialog.add_action_callback('ready') { |_ctx| push_state }
        @dialog.add_action_callback('preview') { |_ctx, json| preview(json) }
        @dialog.add_action_callback('create') { |_ctx, json| on_create(json) }
        @dialog.add_action_callback('cancel') { |_ctx| @dialog.close }
      end

      def show(&on_close)
        @dialog.set_on_closed(&on_close) if on_close
        @dialog.show
      end

      private

      def edit?
        @target.key?(:set)
      end

      def calculator
        @kind == 'cabinet' ? CabinetCalculator : Calculator
      end

      def builder
        @kind == 'cabinet' ? CabinetBuilder : Builder
      end

      def space
        edit? ? JSON.parse(@target[:set].get_attribute(Builder::DICT, 'space')) : @target[:space]
      end

      def params
        raw = if edit?
                @target[:set].get_attribute(Builder::DICT, 'params')
              else
                Sketchup.read_default(PREF_KEY, @kind == 'drawer' ? 'params' : 'cabinet_params', nil)
              end
        calculator.normalize(raw ? JSON.parse(raw) : {})
      rescue JSON::ParserError, ArgumentError
        calculator.normalize({})
      end

      def push_state
        assert_target!
        state = { mode: edit? ? 'edit' : 'create', kind: @kind, space: space, params: params }
        @dialog.execute_script("DMP.load(#{JSON.generate(state)})")
      rescue StandardError => e
        error(e)
      end

      def request(json)
        data = JSON.parse(json)
        raise ArgumentError, 'Parameter tidak valid.' unless data.is_a?(Hash) && data['params'].is_a?(Hash)

        size = @kind == 'cabinet' && !edit? ? data.fetch('space') : space
        [size, data['params'], data['requestId']]
      end

      def preview(json)
        size, p, request_id = request(json)
        plan = calculator.compute(size, p)
        if @kind == 'cabinet'
          parts = plan[:parts] + plan[:doors].flat_map { |door| door[:parts] }
          count = plan[:openings].length
        else
          parts = plan.flat_map { |drawer| drawer[:parts] }
          count = plan.length
        end
        @dialog.execute_script("DMP.preview(#{JSON.generate(parts: parts.map(&:to_h), count: count, requestId: request_id)})")
      rescue StandardError => e
        error(e, request_id)
      end

      def assert_target!
        raise ArgumentError, 'Model/konteks berubah. Tutup panel lalu pilih target kembali.' unless
          Sketchup.active_model == @model && @model.active_path == @edit_path
        raise ArgumentError, 'Set sudah dihapus. Tutup panel lalu pilih kembali.' if edit? && !@target[:set].valid?
        raise ArgumentError, 'Set terkunci. Buka kunci terlebih dahulu.' if edit? && @target[:set].locked?
      end

      def on_create(json)
        assert_target!
        size, p = request(json)
        calculator.compute(size, p)
        set = if edit?
                builder.rebuild(@target[:set], p)
              else
                builder.create(@target[:entities], @target[:transformation], size, p)
              end
        @model.selection.clear
        @model.selection.add(set)
        Sketchup.write_default(PREF_KEY, @kind == 'drawer' ? 'params' : 'cabinet_params', JSON.generate(p))
        @dialog.close
      rescue StandardError => e
        error(e)
      end

      def error(exception, request_id = nil)
        if request_id
          @dialog.execute_script("DMP.error(#{JSON.generate(exception.message)}, #{JSON.generate(request_id)})")
        else
          @dialog.execute_script("DMP.busy(false); DMP.error(#{JSON.generate(exception.message)})")
        end
      end
    end
  end
end
