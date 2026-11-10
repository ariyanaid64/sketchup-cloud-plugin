module SketchupCloud
  module DrawerMakerPro
    # Click the front-bottom-left inner corner of an opening, then the
    # back-top-right inner corner. The box between them is the drawer space.
    class SpaceTool
      MIN_MM = 50

      def initialize(&on_pick)
        @on_pick = on_pick
      end

      def activate
        @ip = Sketchup::InputPoint.new
        @first = nil
        status
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        status
        view.invalidate
      end

      def onCancel(_reason, view)
        @first = nil
        status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        view.tooltip = @ip.tooltip if @ip.valid?
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        @ip.pick(view, x, y)
        return unless @ip.valid?

        if @first.nil?
          @first = @ip.position
          status
        else
          finish(@first, @ip.position)
          @first = nil
          Sketchup.active_model.select_tool(nil)
        end
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        return unless @first && @ip.valid?

        view.drawing_color = Sketchup::Color.new(30, 90, 230)
        view.line_width = 2
        view.draw(GL_LINES, box_edges(@first, @ip.position))
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@first) if @first
        bb.add(@ip.position) if @ip && @ip.valid?
        bb
      end

      private

      def status
        Sketchup.status_text = if @first
                                 'Drawer Maker Pro: click the opposite (back-top-right) inner corner. Esc to restart.'
                               else
                                 'Drawer Maker Pro: click the front-bottom-left inner corner of the opening.'
                               end
      end

      def box_edges(a, b)
        min = Geom::Point3d.new([a.x, b.x].min, [a.y, b.y].min, [a.z, b.z].min)
        max = Geom::Point3d.new([a.x, b.x].max, [a.y, b.y].max, [a.z, b.z].max)
        c = [[min.x, min.y], [max.x, min.y], [max.x, max.y], [min.x, max.y]]
        bottom = c.map { |x, y| Geom::Point3d.new(x, y, min.z) }
        top = c.map { |x, y| Geom::Point3d.new(x, y, max.z) }
        (0..3).flat_map do |i|
          j = (i + 1) % 4
          [bottom[i], bottom[j], top[i], top[j], bottom[i], top[i]]
        end
      end

      def finish(a, b)
        min = Geom::Point3d.new([a.x, b.x].min, [a.y, b.y].min, [a.z, b.z].min)
        width = ((a.x - b.x).abs).to_mm
        depth = ((a.y - b.y).abs).to_mm
        height = ((a.z - b.z).abs).to_mm
        if width < MIN_MM || height < MIN_MM
          UI.messagebox('The picked space is too small. Pick two diagonal inner corners of the opening.')
          return
        end
        if depth < MIN_MM
          input = UI.inputbox(['Space depth (mm)'], ['550'], 'Drawer Maker Pro')
          return unless input
          depth = input[0].to_f
        end

        model = Sketchup.active_model
        # InputPoint positions are global; convert into the open editing context.
        to_local = model.edit_transform.inverse
        transformation = to_local * Geom::Transformation.translation(min)
        space = { 'width' => width.round(1), 'depth' => depth.round(1), 'height' => height.round(1) }
        @on_pick.call(model.active_entities, transformation, space)
      end
    end
  end
end
