# Pure-Ruby drawer geometry (no SketchUp API) so it can be unit tested.
# Millimetres. Space origin: front-bottom-left corner of the opening,
# X = width, Y = depth (into the cabinet), Z = height. Front faces look to -Y.
require_relative 'production'

module SketchupCloud
  module DrawerMakerPro
    module Calculator
      DEFAULTS = {
        'name'             => 'Drawer',
        'layout'           => 'vertical',   # vertical = stacked, horizontal = side by side
        'quantity'         => '3',          # "3", "1:1:2" or "200:1:1" (see split_lengths)
        'front_mode'       => 'inset',      # inset = inside the opening, overlay = over its edges
        'overlay'          => 16.0,         # overlay mode: front extends this far past the opening
        'gap'              => 3.0,          # reveal between fronts (half of it at outer edges)
        'front_thickness'  => 18.0,
        'front_style'      => 'slab',
        'frame_width'      => 60.0,
        'panel_thickness'  => 6.0,
        'handle'           => 'bar',
        'handle_length'    => 128.0,        # bar handle hole centres (c-c)
        'gola_gap'         => 30.0,
        'drawer_type'      => 'wooden',
        'slide_type'       => 'ball_bearing',
        'slide_clearance'  => 12.5,         # only for slide_type custom
        'slide_length'     => 0,            # 0 = longest standard length that fits
        'drawer_depth'     => 0,            # 0 = slide length
        'board_thickness'  => 15.0,         # drawer box sides/front/back
        'bottom_thickness' => 6.0,
        'bottom_raise'     => 12.0,         # groove position above the box underside
        'drawer_bottom'    => 'groove',
        'groove_depth'     => 6.0,
        'drawer_joint'     => 'butt',
        'top_clearance'    => 25.0,
        'bottom_clearance' => 15.0,
        'back_clearance'   => 10.0,
        'box_height'       => 0,            # 0 = auto
        'metal_thickness'  => 13.0,
        'rail_height'      => 90.0,
        'edge_thick'       => 1.0,
        'edge_thin'        => 0.4
      }.freeze
      ENUMS = {
        'layout' => %w[vertical horizontal],
        'front_mode' => %w[inset overlay],
        'front_style' => %w[slab shaker glass],
        'handle' => %w[none push_open bar knob gola j_pull shark_tooth edge_profile],
        'drawer_type' => %w[wooden metal rail],
        'slide_type' => %w[ball_bearing roller undermount custom],
        'drawer_bottom' => %w[groove nailed],
        'drawer_joint' => %w[butt dado]
      }.freeze
      PROFILE_PULLS = %w[j_pull shark_tooth].freeze
      # Values above this are fixed sizes in mm, the rest are ratio weights,
      # so "200:1:1" = 200 mm + two equal shares of the remainder.
      FIXED_THRESHOLD = 20.0

      module_function

      def normalize(params)
        raise ArgumentError, 'Parameter laci harus berupa hash' unless params.nil? || params.is_a?(Hash)

        p = DEFAULTS.merge((params || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v })
        DEFAULTS.each do |key, default|
          if default.is_a?(Numeric)
            p[key] = finite_number(p[key], key)
            raise ArgumentError, "#{key} tidak boleh negatif" if p[key].negative?
          else
            p[key] = p[key].to_s
          end
        end
        ENUMS.each do |key, values|
          raise ArgumentError, "Nilai #{key} tidak valid: #{p[key]}" unless values.include?(p[key])
        end
        %w[board_thickness bottom_thickness front_thickness].each do |key|
          raise ArgumentError, "#{key} harus lebih dari 0" unless p[key].positive?
        end
        if p['front_style'] != 'slab'
          %w[frame_width panel_thickness].each do |key|
            raise ArgumentError, "#{key} harus lebih dari 0" unless p[key].positive?
          end
          raise ArgumentError, 'Tebal panel tidak boleh melebihi tebal muka' if p['panel_thickness'] > p['front_thickness']
          if PROFILE_PULLS.include?(p['handle']) || p['handle'] == 'edge_profile'
            raise ArgumentError, 'Profil J-pull / shark tooth / profil tepi hanya untuk muka slab'
          end
        end
        raise ArgumentError, 'metal_thickness harus lebih dari 0' if p['drawer_type'] == 'metal' && !p['metal_thickness'].positive?
        raise ArgumentError, 'rail_height harus lebih dari 0' if p['drawer_type'] == 'rail' && !p['rail_height'].positive?
        raise ArgumentError, 'Jarak lubang handle harus lebih dari 0' if p['handle'] == 'bar' && !p['handle_length'].positive?
        raise ArgumentError, 'Tinggi celah gola harus lebih dari 0' if p['handle'] == 'gola' && !p['gola_gap'].positive?
        raise ArgumentError, 'slide_clearance harus lebih dari 0' if p['slide_type'] == 'custom' && !p['slide_clearance'].positive?
        if p['slide_length'].positive? && p['slide_length'] < 150
          raise ArgumentError, 'Panjang rel minimal 150 mm (0 = otomatis)'
        end
        if (p['drawer_bottom'] == 'groove' || p['drawer_joint'] == 'dado') &&
           !(p['groove_depth'] > 1 && p['groove_depth'] < p['board_thickness'])
          raise ArgumentError, 'Kedalaman alur harus > 1 mm dan lebih kecil dari tebal papan laci'
        end
        if p['slide_type'] == 'undermount' && p['drawer_bottom'] == 'nailed'
          raise ArgumentError, 'Rel undermount memerlukan dasar laci dalam alur (groove), bukan dipaku di bawah'
        end
        %w[edge_thick edge_thin].each do |key|
          raise ArgumentError, "#{key} maksimal 3 mm" if p[key] > 3
        end
        p
      end

      # Splits `total` (mm) according to a quantity spec. Gaps are handled per cell.
      def split_lengths(spec, total)
        total = finite_number(total, 'total')
        raise ArgumentError, 'Total harus lebih dari 0' unless total.positive?

        tokens = spec.to_s.split(/[:,\s]+/).reject(&:empty?)
        raise ArgumentError, 'Jumlah/pembagian kosong' if tokens.empty?

        if tokens.size == 1 && tokens[0] =~ /\A\d+\z/ && tokens[0].to_f <= FIXED_THRESHOLD
          n = tokens[0].to_i
          raise ArgumentError, 'Jumlah minimal 1' if n < 1

          return Array.new(n, total / n.to_f)
        end

        values = tokens.map do |t|
          raise ArgumentError, "Nilai pembagian tidak valid: #{t}" unless t =~ /\A\d+(\.\d+)?\z/

          t.to_f
        end
        raise ArgumentError, 'Nilai pembagian harus > 0' if values.any? { |v| v <= 0 }

        fixed_total = values.select { |v| v > FIXED_THRESHOLD }.sum
        weights = values.reject { |v| v > FIXED_THRESHOLD }.sum
        remainder = total - fixed_total
        if remainder < -1e-6 || (weights.zero? && remainder.abs > 0.5)
          raise ArgumentError, format('Ukuran tetap (%.1f mm) tidak sesuai ruang (%.1f mm)', fixed_total, total)
        end

        values.map { |v| v > FIXED_THRESHOLD ? v : remainder * v / weights }
      end

      # space: { 'width' => mm, 'depth' => mm, 'height' => mm }
      # Returns drawers: { index:, cell:, parts: (moving), fixed: (stay in the
      # opening: slide cabinet members, gola profiles, latches), travel: mm }.
      def compute(space, params)
        p = normalize(params)
        w = finite_number(space_value(space, 'width'), 'width')
        d = finite_number(space_value(space, 'depth'), 'depth')
        h = finite_number(space_value(space, 'height'), 'height')
        raise ArgumentError, 'Ruang terlalu kecil' if w < 50 || d < 50 || h < 50

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
          name = "#{p['name']} #{i + 1}"
          front = standalone_front(cell, p, name)
          # The gola channel occupies the top of the cell, so the box stays below it.
          box_zone = cell.merge('height' => cell['height'] - (p['handle'] == 'gola' ? p['gola_gap'] : 0.0))
          gola_kind = vertical && i == lengths.size - 1 ? 'L' : 'C'
          unit = drawer_unit(name, front, box_zone, p, gola: gola_profile_spec(cell, front, p, gola_kind))
          { index: i + 1, cell: cell, parts: unit[:moving], fixed: unit[:fixed], travel: unit[:travel] }
        end
      end

      def standalone_front(cell, p, name)
        g = p['gap']
        ft = p['front_thickness']
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
        raise ArgumentError, "#{name}: muka terlalu kecil" if fw < 60 || fh < 60

        { x: fx, y: fy, z: fz, w: fw, h: fh, box_y: box_y }
      end

      def gola_profile_spec(cell, front, p, kind)
        return nil unless p['handle'] == 'gola'

        { kind: kind, x: cell['x'], width: cell['width'], z: front[:z] + front[:h] + p['gap'] / 2.0,
          height: p['gola_gap'] }
      end

      # One drawer: front + pull + box + slides. `opening` bounds the box
      # ({'x','z','width','height','depth'}); front is {x,y,z,w,h,box_y}.
      def drawer_unit(name, front, opening, p, gola: nil)
        moving = front_parts("#{name} - Front", front[:x], front[:y], front[:z], front[:w], front[:h], p,
                             pull_edge: 'top', grain: 'x')
        moving.concat(pull_parts(name, front, p, kind: :drawer))
        box = drawer_box(name, opening, front[:box_y], p)
        moving.concat(box[:moving])
        fixed = box[:fixed]
        if gola
          section = Profiles.gola_section(gola[:kind], gola[:height])
          fixed << Production.hardware("#{name} - Profil gola #{gola[:kind]}", 'gola',
                                       "Profil gola #{gola[:kind]} aluminium", gola[:x], 0.0, gola[:z],
                                       gola[:width], Production::GOLA_DEPTH, gola[:height],
                                       shape: 'profile', axis: 'x', profile: section,
                                       length: gola[:width], material: 'aluminium')
        end
        if p['handle'] == 'push_open'
          room = opening['depth'] - box[:end_y]
          if room >= 2
            fixed << Production.cylinder("#{name} - Push latch", 'push_latch', 'Push-open / tip-on latch',
                                         [opening['x'] + opening['width'] / 2.0, box[:end_y],
                                          box[:z] + 20], 'y', 12.0, [room - 1, 40.0].min)
          end
        end
        { moving: moving, fixed: fixed, travel: box[:travel] }
      end

      # Bands every edge of a front; profiled pull edges are machined, not banded.
      def front_band(p, len_axis, skip_edge = nil)
        e = p['edge_thick']
        edges = { 'top' => e, 'bottom' => e, 'left' => e, 'right' => e }
        edges[skip_edge] = 0.0 if skip_edge
        if len_axis == 'x'
          { l1: edges['top'], l2: edges['bottom'], w1: edges['left'], w2: edges['right'] }
        else
          { l1: edges['left'], l2: edges['right'], w1: edges['bottom'], w2: edges['top'] }
        end
      end

      # Generates a door or drawer face (without bar/knob hardware).
      # pull_edge: 'top' | 'bottom' | 'left' | 'right' (used by profile pulls).
      def front_parts(name, x, y, z, width, height, params, pull_edge: 'top', grain: 'z')
        p = normalize(params)
        x = finite_number(x, 'x')
        y = finite_number(y, 'y')
        z = finite_number(z, 'z')
        width = finite_number(width, 'width')
        height = finite_number(height, 'height')
        ft = p['front_thickness']
        raise ArgumentError, "#{name}: ukuran muka harus lebih dari 0" unless width.positive? && height.positive?

        parts = []
        if p['handle'] == 'edge_profile'
          eh = Production::EDGE_PROFILE_HEIGHT
          section = Profiles.edge_profile_section(ft, eh)
          hw_x, hw_z, hw_w, hw_h = x, z, width, height
          case pull_edge
          when 'top' then height -= eh; hw_z = z + height; hw_h = eh
          when 'bottom' then z += eh; height -= eh; hw_h = eh
          when 'right' then width -= eh; hw_x = x + width; hw_w = eh
          when 'left' then x += eh; width -= eh; hw_w = eh
          end
          raise ArgumentError, "#{name}: muka terlalu kecil untuk profil tepi" if width < 40 || height < 40

          axis, points = Profiles.place(section, pull_edge, hw_w, hw_h)
          length = %w[top bottom].include?(pull_edge) ? hw_w : hw_h
          parts << Production.hardware("#{name} - Profil handle", 'handle', 'Profil handle aluminium tepi',
                                       hw_x, y, hw_z, hw_w, ft + 8, hw_h, shape: 'profile', axis: axis,
                                       profile: points, length: length, material: 'aluminium')
        end

        if p['front_style'] == 'slab'
          if PROFILE_PULLS.include?(p['handle'])
            size = %w[top bottom].include?(pull_edge) ? height : width
            section = Profiles.front_section(p['handle'], ft, size)
            axis, points = Profiles.place(section, pull_edge, width, height)
            parts << Production.panel(name, 'front', x, y, z, width, ft, height, len_axis: grain,
                                      band: front_band(p, grain, pull_edge), material: 'front',
                                      shape: 'profile', axis: axis, profile: points)
          else
            parts << Production.panel(name, 'front', x, y, z, width, ft, height, len_axis: grain,
                                      band: front_band(p, grain), material: 'front')
          end
          return parts
        end

        frame = p['frame_width']
        inner_w = width - 2 * frame
        inner_h = height - 2 * frame
        raise ArgumentError, "#{name}: muka terlalu kecil untuk lebar bingkai" if inner_w <= 0 || inner_h <= 0

        panel_t = p['panel_thickness']
        parts << Production.panel("#{name} - Left Stile", 'front', x, y, z, frame, ft, height, len_axis: 'z', material: 'front')
        parts << Production.panel("#{name} - Right Stile", 'front', x + width - frame, y, z, frame, ft, height,
                                  len_axis: 'z', material: 'front')
        parts << Production.panel("#{name} - Bottom Rail", 'front', x + frame, y, z, inner_w, ft, frame,
                                  len_axis: 'x', material: 'front')
        parts << Production.panel("#{name} - Top Rail", 'front', x + frame, y, z + height - frame, inner_w, ft, frame,
                                  len_axis: 'x', material: 'front')
        if p['front_style'] == 'glass'
          parts << Production.panel("#{name} - Glass", 'glass', x + frame, y + ft - panel_t, z + frame,
                                    inner_w, panel_t, inner_h, len_axis: 'z', material: 'glass')
        else
          parts << Production.panel("#{name} - Recessed Panel", 'front_panel', x + frame, y + ft - panel_t, z + frame,
                                    inner_w, panel_t, inner_h, len_axis: 'z', material: 'front')
        end
        parts
      end

      # Bar or knob. kind :drawer => horizontal, centred; kind :door => vertical
      # near the free edge (hinge_side 'left'/'right'), placed towards pull_edge.
      def pull_parts(name, front, p, kind:, hinge_side: 'left', pull_edge: 'top')
        return [] unless %w[bar knob].include?(p['handle'])

        fy = front[:y]
        fx = front[:x]
        fz = front[:z]
        fw = front[:w]
        fh = front[:h]
        if kind == :drawer
          cx = fx + fw / 2.0
          cz = fh <= 300 ? fz + fh / 2.0 : fz + fh - 50.0
        else
          cx = hinge_side == 'left' ? fx + fw - 40.0 : fx + 40.0
          cz = case pull_edge
               when 'top' then fz + fh - 60.0 - (p['handle'] == 'bar' ? p['handle_length'] / 2.0 + 10 : 0)
               when 'bottom' then fz + 60.0 + (p['handle'] == 'bar' ? p['handle_length'] / 2.0 + 10 : 0)
               else fz + fh / 2.0
               end
        end

        if p['handle'] == 'knob'
          return [Production.cylinder("#{name} - Knob", 'knob', 'Knob ø30', [cx, fy - 28.0, cz], 'y', 30.0, 28.0)]
        end

        cc = p['handle_length']
        grip = cc + 20.0
        span = kind == :drawer ? fw : fh
        if grip > span - 20
          raise ArgumentError, format('%s: handle c-c %.0f mm terlalu panjang untuk muka %.0f mm', name, cc, span)
        end

        desc = format('Handle bar c-c %.0f mm', cc)
        if kind == :drawer
          [Production.hardware("#{name} - Handle Standoff L", 'handle', desc, cx - cc / 2.0 - 5, fy - 22, cz - 5,
                               10, 22, 10, qty: 0),
           Production.hardware("#{name} - Handle Standoff R", 'handle', desc, cx + cc / 2.0 - 5, fy - 22, cz - 5,
                               10, 22, 10, qty: 0),
           Production.hardware("#{name} - Handle Grip", 'handle', desc, cx - grip / 2.0, fy - 32, cz - 5,
                               grip, 10, 10)]
        else
          [Production.hardware("#{name} - Handle Standoff B", 'handle', desc, cx - 5, fy - 22, cz - cc / 2.0 - 5,
                               10, 22, 10, qty: 0),
           Production.hardware("#{name} - Handle Standoff T", 'handle', desc, cx - 5, fy - 22, cz + cc / 2.0 - 5,
                               10, 22, 10, qty: 0),
           Production.hardware("#{name} - Handle Grip", 'handle', desc, cx - 5, fy - 32, cz - grip / 2.0,
                               10, 10, grip)]
        end
      end

      def slide_clearance(p)
        p['slide_type'] == 'custom' ? p['slide_clearance'] : Production::SLIDE_CLEARANCE.fetch(p['slide_type'])
      end

      # Box, bottom and slides. Returns {moving:, fixed:, travel:, end_y:, z:}.
      def drawer_box(name, opening, box_y0, p)
        t = p['board_thickness']
        bt = p['bottom_thickness']
        metal = p['drawer_type'] == 'metal'
        st = metal ? p['metal_thickness'] : t
        c = slide_clearance(p)
        bw = opening['width'] - 2 * c
        bx = opening['x'] + c
        bz = opening['z'] + p['bottom_clearance']
        available = opening['depth'] - box_y0 - p['back_clearance']
        if p['drawer_depth'].positive?
          raise ArgumentError, format('%s: kedalaman laci %.0f mm melebihi ruang %.0f mm', name, p['drawer_depth'], available) if p['drawer_depth'] > available + 1e-6

          depth = p['drawer_depth']
          slide = Production.slide_length(depth, p['slide_length'])
        else
          slide = Production.slide_length(available, p['slide_length'])
          depth = slide
        end
        auto_h = opening['height'] - p['top_clearance'] - p['bottom_clearance']
        bh = p['box_height'].positive? ? [p['box_height'], auto_h].min : auto_h
        raise ArgumentError, "#{name}: ruang terlalu sempit untuk kotak laci" if bw < 2 * st + 60 || depth < 2 * t + 60
        raise ArgumentError, format('%s: tinggi kotak laci %.0f mm terlalu kecil (min 60 mm)', name, bh) if bh < 60

        nailed = p['drawer_bottom'] == 'nailed'
        raise_eff = p['slide_type'] == 'undermount' ? [p['bottom_raise'], Production::UNDERMOUNT_RECESS].max : p['bottom_raise']
        wall_z = nailed ? bz + bt : bz
        wall_h = nailed ? bh - bt : bh
        side_h = p['drawer_type'] == 'rail' ? wall_h - p['rail_height'] : wall_h
        if !nailed && raise_eff + bt + 20 > side_h
          raise ArgumentError, "#{name}: posisi alur dasar + tebal dasar terlalu tinggi untuk sisi laci"
        end
        raise ArgumentError, "#{name}: rail_height terlalu besar untuk tinggi laci" if side_h < 40

        thin = p['edge_thin']
        parts = []
        side_role = metal ? 'metal_side' : 'side'
        side_material = metal ? 'metal' : 'drawer_box'
        side_band = metal ? {} : { l1: thin }
        parts << Production.panel("#{name} - Side L", side_role, bx, box_y0, wall_z, st, depth, side_h,
                                  len_axis: 'y', band: side_band, material: side_material)
        parts << Production.panel("#{name} - Side R", side_role, bx + bw - st, box_y0, wall_z, st, depth, side_h,
                                  len_axis: 'y', band: side_band, material: side_material)

        inner = bw - 2 * st
        joint = !metal && p['drawer_joint'] == 'dado' ? [p['groove_depth'], st / 2.0].min : 0.0
        fb_x = bx + st - joint
        fb_len = inner + 2 * joint
        parts << Production.panel("#{name} - Sub Front", 'sub_front', fb_x, box_y0, wall_z, fb_len, t, wall_h,
                                  len_axis: 'x', band: { l1: thin }, material: 'drawer_box')
        parts << Production.panel("#{name} - Back", 'back', fb_x, box_y0 + depth - t, wall_z, fb_len, t, wall_h,
                                  len_axis: 'x', band: { l1: thin }, material: 'drawer_box')

        if nailed
          parts << Production.panel("#{name} - Bottom", 'bottom', bx, box_y0, bz, bw, depth, bt,
                                    len_axis: bw >= depth ? 'x' : 'y', material: 'drawer_bottom')
        else
          gd = p['groove_depth']
          side_into = metal ? 0.0 : gd - 1
          bottom_w = inner + 2 * side_into
          bottom_d = depth - 2 * t + 2 * (gd - 1)
          parts << Production.panel("#{name} - Bottom", 'bottom', bx + st - side_into, box_y0 + t - (gd - 1),
                                    bz + raise_eff, bottom_w, bottom_d, bt,
                                    len_axis: bottom_w >= bottom_d ? 'x' : 'y', material: 'drawer_bottom')
        end

        if p['drawer_type'] == 'rail'
          rod_z = wall_z + wall_h - 5.0
          [bx + st / 2.0, bx + bw - st / 2.0].each_with_index do |rx, i|
            parts << Production.cylinder("#{name} - Gallery Rail #{i.zero? ? 'L' : 'R'}", 'rail',
                                         'Galeri rail ø10 (per sisi)', [rx, box_y0, rod_z], 'y', 10.0, depth)
          end
        end

        fixed = []
        desc = format('%s NL %.0f mm (pasang)', Production::SLIDE_NAMES.fetch(p['slide_type']), slide)
        if p['slide_type'] == 'undermount'
          [[bx + st, 'L'], [bx + bw - st - 25.0, 'R']].each do |sx, side|
            fixed << Production.hardware("#{name} - Slide #{side}", 'slide', desc, sx, box_y0, bz,
                                         25.0, slide - 10.0, raise_eff - 1.0, qty: 0.5)
          end
        else
          height = p['slide_type'] == 'roller' ? 25.0 : [45.0, side_h - 15.0].min
          raise ArgumentError, "#{name}: sisi laci terlalu rendah untuk rel" if height < 20

          sz = p['slide_type'] == 'roller' ? wall_z : wall_z + [10.0, (side_h - height) / 2.0].min
          right = opening['x'] + opening['width']
          # [cabinet member x, drawer member x] per side; the drawer member sits against the box.
          [[opening['x'], opening['x'] + c / 2.0, 'L'], [right - c / 2.0, right - c, 'R']].each do |cab_x, box_x, side|
            fixed << Production.hardware("#{name} - Slide #{side} (kabinet)", 'slide', desc, cab_x, box_y0, sz,
                                         c / 2.0, slide, height, qty: 0.5)
            parts << Production.hardware("#{name} - Slide #{side} (laci)", 'slide', desc, box_x, box_y0, sz,
                                         c / 2.0, slide, height, qty: 0)
          end
        end

        ratio = %w[ball_bearing undermount].include?(p['slide_type']) ? 0.9 : 0.75
        { moving: parts, fixed: fixed, travel: (slide * ratio).round(1), end_y: box_y0 + depth, z: bz }
      end

      def finite_number(value, label)
        number = Float(value)
        raise ArgumentError, "#{label} harus berupa angka" unless number.finite?

        number
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} harus berupa angka"
      end

      def space_value(space, key)
        raise ArgumentError, 'Ukuran ruang tidak valid' unless space.is_a?(Hash)

        space[key] || space[key.to_sym]
      end
    end
  end
end
