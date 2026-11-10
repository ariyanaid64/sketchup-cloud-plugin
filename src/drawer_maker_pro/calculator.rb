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
        'name'            => 'Drawer'
      }.freeze

      # Values above this are fixed sizes in mm, the rest are ratio weights,
      # so "200:1:1" = 200 mm + two equal shares of the remainder.
      FIXED_THRESHOLD = 20.0

      module_function

      def normalize(params)
        p = DEFAULTS.merge(params.each_with_object({}) { |(k, v), h| h[k.to_s] = v })
        DEFAULTS.each do |k, v|
          p[k] = p[k].to_f if v.is_a?(Numeric)
          p[k] = p[k].to_s if v.is_a?(String)
        end
        p
      end

      # Splits `total` (mm) according to a quantity spec, accounting for nothing
      # else (gaps are handled per cell). Returns an array of lengths.
      def split_lengths(spec, total)
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
        w = space['width'].to_f
        d = space['depth'].to_f
        h = space['height'].to_f
        raise ArgumentError, 'Space is too small' if w < 50 || d < 50 || h < 50

        vertical = p['layout'] != 'horizontal'
        lengths = split_lengths(p['quantity'], vertical ? h : w)
        # Stack from the bottom up / left to right; the user writes the spec top-down.
        lengths = lengths.reverse if vertical

        offset = 0.0
        lengths.each_with_index.map do |len, i|
          cell = if vertical
                   { 'x' => 0.0, 'z' => offset, 'width' => w, 'height' => len, 'depth' => d }
                 else
                   { 'x' => offset, 'z' => 0.0, 'width' => len, 'height' => h, 'depth' => d }
                 end
          offset += len
          { index: i + 1, cell: cell, parts: drawer_parts(cell, p, i + 1) }
        end
      end

      def drawer_parts(cell, p, index)
        g = p['gap']
        ft = p['front_thickness']
        t = p['board_thickness']
        bt = p['bottom_thickness']
        name = "#{p['name']} #{index}"

        # Front panel
        if p['front_mode'] == 'overlay'
          ov = p['overlay']
          fx = cell['x'] - ov + g / 2.0
          fz = cell['z'] - ov + g / 2.0
          fw = cell['width'] + 2 * ov - g
          fh = cell['height'] + 2 * ov - g
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

        parts = [Part.new("#{name} - Front", 'front', fx, fy, fz, fw, ft, fh)]

        # Drawer box
        max_depth = cell['depth'] - box_y - p['back_clearance']
        depth = p['drawer_depth'] > 0 ? [p['drawer_depth'], max_depth].min : max_depth
        bw = cell['width'] - 2 * p['slide_clearance']
        bz = cell['z'] + p['bottom_clearance']
        auto_h = cell['height'] - p['top_clearance'] - p['bottom_clearance']
        bh = p['box_height'] > 0 ? [p['box_height'], auto_h].min : auto_h
        if bw < 2 * t + 20 || bh < bt + 20 || depth < 2 * t + 20
          raise ArgumentError, "#{name}: space is too small for a drawer box"
        end

        bx = cell['x'] + p['slide_clearance']
        inner = bw - 2 * t
        parts << Part.new("#{name} - Side L", 'side', bx, box_y, bz, t, depth, bh)
        parts << Part.new("#{name} - Side R", 'side', bx + bw - t, box_y, bz, t, depth, bh)
        parts << Part.new("#{name} - Sub Front", 'sub_front', bx + t, box_y, bz, inner, t, bh)
        # Back sits on the bottom panel so the bottom can slide in from behind.
        back_z = bz + p['bottom_raise'] + bt
        parts << Part.new("#{name} - Back", 'back', bx + t, box_y + depth - t, back_z, inner, t, bh - p['bottom_raise'] - bt)
        parts << Part.new("#{name} - Bottom", 'bottom', bx + t, box_y + t, bz + p['bottom_raise'], inner, depth - t, bt)

        if p['handle'] == 'bar'
          hl = [p['handle_length'], fw - 40].min
          hz = fz + fh - [40.0, fh / 2.0].min
          parts << Part.new("#{name} - Handle", 'handle', fx + (fw - hl) / 2.0, fy - 30, hz - 6, hl, 30, 12)
        end
        parts
      end
    end
  end
end
