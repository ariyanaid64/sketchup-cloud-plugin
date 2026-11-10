# Pure-Ruby drawer geometry. No SketchUp API here so it can be unit tested.
# All values are millimetres. Space coordinates: origin at the front-bottom-left
# inner corner of the opening, X = width, Y = depth (into the cabinet), Z = height.
module SketchupCloud
  module DrawerMakerPro
    Part = Struct.new(:name, :role, :x, :y, :z, :dx, :dy, :dz) do
      # Cut-list dimensions: length >= width, thickness = smallest side.
      def cut_size
        dims = [dx, dy, dz].sort
        { length: dims[2], width: dims[1], thickness: dims[0] }
      end

      def to_h
        super.merge(cut_size)
      end
    end

    module Calculator
      DEFAULTS = {
        'layout'          => 'vertical',   # vertical = stacked, horizontal = side by side
        'quantity'        => '3',          # "3", "1:1:2" or "200:1:1" (see split_lengths)
        'drawer_depth'    => 0,            # 0 = auto (space depth - front - back clearance)
        'board_thickness' => 15.0,         # drawer box sides/front/back
        'bottom_thickness'=> 9.0,
        'bottom_raise'    => 12.0,         # bottom panel height above box underside
        'front_thickness' => 18.0,
        'front_mode'      => 'inset',      # inset = inside the opening, overlay = in front of it
        'overlay'         => 0.0,          # overlay mode: how far the front extends past the opening
        'gap'             => 3.0,          # gap between / around fronts
        'slide_clearance' => 12.5,         # per side, between box and cabinet side
        'top_clearance'   => 25.0,         # box height = front height - top - bottom clearance
        'bottom_clearance'=> 15.0,
        'back_clearance'  => 10.0,
        'box_height'      => 0,            # 0 = auto
        'handle'          => 'bar',        # none | bar | gola
        'handle_length'   => 128.0,
        'gola_gap'        => 30.0,
        'drawer_type'     => 'wooden',
        'front_style'     => 'slab',
        'frame_width'     => 60.0,
        'panel_thickness' => 6.0,
        'metal_thickness' => 2.0,
        'rail_height'     => 90.0,
        'name'            => 'Drawer'
      }.freeze
      ENUMS = {
        'layout' => %w[vertical horizontal],
        'front_mode' => %w[inset overlay],
        'handle' => %w[none bar gola],
        'drawer_type' => %w[wooden metal rail],
        'front_style' => %w[slab shaker glass]
      }.freeze

      # Values above this are fixed sizes in mm, the rest are ratio weights,
      # so "200:1:1" = 200 mm + two equal shares of the remainder.
      FIXED_THRESHOLD = 20.0

      module_function

      def normalize(params)
        p = DEFAULTS.merge((params || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v })
        DEFAULTS.each do |k, v|
          if v.is_a?(Numeric)
            begin
              p[k] = Float(p[k])
            rescue ArgumentError, TypeError
              raise ArgumentError, "#{k} must be a finite number"
            end
            raise ArgumentError, "#{k} must be a finite number" unless p[k].finite?
            raise ArgumentError, "#{k} must be non-negative" if p[k] < 0
          end
          p[k] = p[k].to_s if v.is_a?(String)
        end
        ENUMS.each do |key, values|
          raise ArgumentError, "Invalid #{key}: #{p[key]}" unless values.include?(p[key])
        end
        %w[board_thickness bottom_thickness front_thickness].each do |key|
          raise ArgumentError, "#{key} must be greater than zero" unless p[key] > 0
        end
        if p['front_style'] != 'slab'
          %w[frame_width panel_thickness].each do |key|
            raise ArgumentError, "#{key} must be greater than zero" unless p[key] > 0
          end
          raise ArgumentError, 'panel_thickness cannot exceed front_thickness' if p['panel_thickness'] > p['front_thickness']
        end
        raise ArgumentError, 'metal_thickness must be greater than zero' if p['drawer_type'] == 'metal' && !p['metal_thickness'].positive?
        raise ArgumentError, 'rail_height must be greater than zero' if p['drawer_type'] == 'rail' && !p['rail_height'].positive?
        raise ArgumentError, 'handle_length must be greater than zero for a bar handle' if p['handle'] == 'bar' && !p['handle_length'].positive?
        raise ArgumentError, 'gola_gap must be greater than zero for a gola handle' if p['handle'] == 'gola' && !p['gola_gap'].positive?
        p
      end

      # Splits `total` (mm) according to a quantity spec, accounting for nothing
      # else (gaps are handled per cell). Returns an array of lengths.
      def split_lengths(spec, total)
        total = finite_number(total, 'total')
        raise ArgumentError, 'Total must be greater than zero' unless total.positive?
        tokens = spec.to_s.split(/[:,\s]+/).reject(&:empty?)
        raise ArgumentError, 'Quantity is empty' if tokens.empty?

        if tokens.size == 1 && tokens[0] =~ /\A\d+\z/ && tokens[0].to_f <= FIXED_THRESHOLD
          n = tokens[0].to_i
          raise ArgumentError, 'Quantity must be at least 1' if n < 1
          return Array.new(n, total / n.to_f)
        end

        values = tokens.map do |t|
          raise ArgumentError, "Invalid quantity value: #{t}" unless t =~ /\A\d+(\.\d+)?\z/
          t.to_f
        end
        raise ArgumentError, 'Quantity values must be > 0' if values.any? { |v| v <= 0 }

        fixed_total = values.select { |v| v > FIXED_THRESHOLD }.sum
        weights = values.reject { |v| v > FIXED_THRESHOLD }.sum
        remainder = total - fixed_total
        if remainder < -1e-6 || (weights.zero? && (remainder.abs > 0.5))
          raise ArgumentError, format('Fixed sizes (%.1f mm) do not fit the space (%.1f mm)', fixed_total, total)
        end

        values.map { |v| v > FIXED_THRESHOLD ? v : remainder * v / weights }
      end

      # space: { 'width' => mm, 'depth' => mm, 'height' => mm }
      # Returns an array of drawers: { index:, cell: {...}, parts: [Part] }.
      def compute(space, params)
        p = normalize(params)
        w = finite_number(space_value(space, 'width'), 'width')
        d = finite_number(space_value(space, 'depth'), 'depth')
        h = finite_number(space_value(space, 'height'), 'height')
        raise ArgumentError, 'Space is too small' if w < 50 || d < 50 || h < 50

        vertical = p['layout'] == 'vertical'
        lengths = split_lengths(p['quantity'], vertical ? h : w)
        # Stack from the bottom up / left to right; the user writes the spec top-down.
        lengths = lengths.reverse if vertical

        offset = 0.0
        lengths.each_with_index.map do |len, i|
          cell = if vertical
                   { 'x' => 0.0, 'z' => offset, 'width' => w, 'height' => len, 'depth' => d,
                     'left_edge' => true, 'right_edge' => true,
                     'bottom_edge' => i.zero?, 'top_edge' => i == lengths.size - 1 }
                 else
                   { 'x' => offset, 'z' => 0.0, 'width' => len, 'height' => h, 'depth' => d,
                     'left_edge' => i.zero?, 'right_edge' => i == lengths.size - 1,
                     'bottom_edge' => true, 'top_edge' => true }
                 end
          offset += len
          { index: i + 1, cell: cell, parts: drawer_parts(cell, p, i + 1) }
        end
      end

      def drawer_parts(cell, p, index)
        p = normalize(p)
        g = p['gap']
        ft = p['front_thickness']
        t = p['board_thickness']
        bt = p['bottom_thickness']
        name = "#{p['name']} #{index}"

        # Only perimeter cells receive overlay; internal edges retain the gap.
        if p['front_mode'] == 'overlay'
          ov = p['overlay']
          left = cell.fetch('left_edge', true) ? ov - g / 2.0 : -g / 2.0
          right = cell.fetch('right_edge', true) ? ov - g / 2.0 : -g / 2.0
          bottom = cell.fetch('bottom_edge', true) ? ov - g / 2.0 : -g / 2.0
          top = cell.fetch('top_edge', true) ? ov - g / 2.0 : -g / 2.0
          fx = cell['x'] - left
          fz = cell['z'] - bottom
          fw = cell['width'] + left + right
          fh = cell['height'] + bottom + top
          fy = -ft
          box_y = 0.0
        else
          fx = cell['x'] + g / 2.0
          fz = cell['z'] + g / 2.0
          fw = cell['width'] - g
          fh = cell['height'] - g
          fy = 0.0
          box_y = ft
        end
        fh -= p['gola_gap'] if p['handle'] == 'gola'
        raise ArgumentError, "#{name}: front is too small" if fw < 30 || fh < 30

        parts = front_parts("#{name} - Front", fx, fy, fz, fw, fh, p)

        # Drawer box
        max_depth = cell['depth'] - box_y - p['back_clearance']
        depth = p['drawer_depth'] > 0 ? [p['drawer_depth'], max_depth].min : max_depth
        bw = cell['width'] - 2 * p['slide_clearance']
        bz = cell['z'] + p['bottom_clearance']
        auto_h = cell['height'] - p['top_clearance'] - p['bottom_clearance']
        bh = p['box_height'] > 0 ? [p['box_height'], auto_h].min : auto_h
        side_t = p['drawer_type'] == 'metal' ? p['metal_thickness'] : t
        inner = bw - 2 * side_t
        if bw < 2 * side_t + 20 || bh < bt + 20 || depth < 2 * t + 20
          raise ArgumentError, "#{name}: space is too small for a drawer box"
        end
        if p['bottom_raise'] + bt >= bh
          raise ArgumentError, "#{name}: bottom_raise and bottom_thickness leave no back panel"
        end
        rail_section = 10.0
        side_h = p['drawer_type'] == 'rail' ? bh - p['rail_height'] - rail_section : bh
        if p['drawer_type'] == 'rail' && (side_h < p['bottom_raise'] + bt || p['rail_height'] <= 0)
          raise ArgumentError, "#{name}: rail_height must leave a positive opening and side above the bottom"
        end

        bx = cell['x'] + p['slide_clearance']
        side_role = p['drawer_type'] == 'metal' ? 'metal_side' : 'side'
        parts << make_part("#{name} - Side L", side_role, bx, box_y, bz, side_t, depth, side_h)
        parts << make_part("#{name} - Side R", side_role, bx + bw - side_t, box_y, bz, side_t, depth, side_h)
        parts << make_part("#{name} - Sub Front", 'sub_front', bx + side_t, box_y, bz, inner, t, bh)
        # Back sits on the bottom panel so the bottom can slide in from behind.
        back_z = bz + p['bottom_raise'] + bt
        parts << make_part("#{name} - Back", 'back', bx + side_t, box_y + depth - t, back_z, inner, t, bh - p['bottom_raise'] - bt)
        parts << make_part("#{name} - Bottom", 'bottom', bx + side_t, box_y + t, bz + p['bottom_raise'], inner, depth - t, bt)

        if p['drawer_type'] == 'rail'
          rail_width = [side_t, rail_section].min
          rail_x_offset = (side_t - rail_width) / 2.0
          rail_z = bz + bh - rail_section
          parts << make_part("#{name} - Gallery Rail L", 'rail', bx + rail_x_offset, box_y, rail_z,
                             rail_width, depth, rail_section)
          parts << make_part("#{name} - Gallery Rail R", 'rail', bx + bw - side_t + rail_x_offset,
                             box_y, rail_z, rail_width, depth, rail_section)
        end

        if p['handle'] == 'bar'
          hl = [p['handle_length'], fw - 40].min
          hz = fz + fh - [40.0, fh / 2.0].min
          hx = fx + (fw - hl) / 2.0
          stand_width = [8.0, hl / 4.0].min
          stand_offset = [12.0, (hl - stand_width) / 2.0].min
          parts << make_part("#{name} - Handle Standoff L", 'handle', hx + stand_offset, fy - 22, hz - 6,
                             stand_width, 22, 12)
          parts << make_part("#{name} - Handle Standoff R", 'handle', hx + hl - stand_offset - stand_width,
                             fy - 22, hz - 6, stand_width, 22, 12)
          parts << make_part("#{name} - Handle Grip", 'handle', hx, fy - 30, hz - 4, hl, 8, 8)
        end
        parts
      end

      # Generates a cabinet door or drawer face without a handle.
      def front_parts(name, x, y, z, width, height, params)
        p = normalize(params)
        x = finite_number(x, 'x')
        y = finite_number(y, 'y')
        z = finite_number(z, 'z')
        width = finite_number(width, 'width')
        height = finite_number(height, 'height')
        ft = p['front_thickness']
        raise ArgumentError, 'Front dimensions must be greater than zero' unless width.positive? && height.positive?
        return [make_part(name, 'front', x, y, z, width, ft, height)] if p['front_style'] == 'slab'

        frame = p['frame_width']
        inner_w = width - 2 * frame
        inner_h = height - 2 * frame
        if inner_w <= 0 || inner_h <= 0
          raise ArgumentError, 'Front is too small for the selected frame_width'
        end
        panel_t = p['panel_thickness']
        panel_y = y + ft - panel_t
        parts = [
          make_part("#{name} - Left Stile", 'front', x, y, z, frame, ft, height),
          make_part("#{name} - Right Stile", 'front', x + width - frame, y, z, frame, ft, height),
          make_part("#{name} - Bottom Rail", 'front', x + frame, y, z, inner_w, ft, frame),
          make_part("#{name} - Top Rail", 'front', x + frame, y, z + height - frame, inner_w, ft, frame)
        ]
        panel_role = p['front_style'] == 'glass' ? 'glass' : 'front_panel'
        parts << make_part("#{name} - #{panel_role == 'glass' ? 'Glass' : 'Recessed Panel'}", panel_role,
                           x + frame, panel_y, z + frame, inner_w, panel_t, inner_h)
        parts
      end

      def finite_number(value, label)
        number = Float(value)
        raise ArgumentError, "#{label} must be a finite number" unless number.finite?
        number
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} must be a finite number"
      end
      private_class_method :finite_number

      def space_value(space, key)
        space[key] || space[key.to_sym]
      end
      private_class_method :space_value

      def make_part(name, role, x, y, z, dx, dy, dz)
        dims = [dx, dy, dz].map { |dimension| finite_number(dimension, 'part dimension') }
        raise ArgumentError, "#{name}: generated dimensions must be greater than zero" unless dims.all?(&:positive?)
        [x, y, z].each { |coordinate| finite_number(coordinate, 'part coordinate') }
        Part.new(name, role, x, y, z, *dims)
      end
      private_class_method :make_part
    end
  end
end
