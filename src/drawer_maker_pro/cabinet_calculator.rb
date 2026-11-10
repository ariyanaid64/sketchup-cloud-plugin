# Pure-Ruby cabinet geometry (frameless / 32 mm system). Millimetres.
# Origin: the cabinet's external front-bottom-left corner; X = width,
# Y = depth (towards the back), Z = height. Fronts face -Y.
require_relative 'calculator'

module SketchupCloud
  module DrawerMakerPro
    module CabinetCalculator
      DEFAULTS = {
        'name' => 'Cabinet',
        'cabinet_type' => 'base',
        'board_thickness' => 18.0,
        'back_thickness' => 6.0,
        'back_mode' => 'groove',
        'back_groove_depth' => 8.0,
        'back_inset' => 10.0,
        'base_type' => 'plinth',
        'plinth_height' => 100.0,
        'plinth_setback' => 50.0,
        'top_type' => 'full',
        'rail_width' => 100.0,
        'carcass_joint' => 'minifix',
        'dado_depth' => 8.0,
        'columns' => '2',
        'bay_fronts' => '',
        'shelves' => 1,
        'shelf_type' => 'adjustable',
        'shelf_setback' => 20.0,
        'door_mode' => 'auto',
        'door_fit' => 'full_overlay',
        'gap' => 3.0,
        'hinge_angle' => 110.0,
        'cup_distance' => 4.0,
        'front_style' => 'shaker',
        'front_thickness' => 18.0,
        'frame_width' => 60.0,
        'panel_thickness' => 6.0,
        'handle' => 'bar',
        'handle_length' => 128.0,
        'gola_gap' => 30.0,
        'pull_edge' => 'auto',
        'drawer_type' => 'wooden',
        'slide_type' => 'ball_bearing',
        'slide_clearance' => 12.5,
        'slide_length' => 0,
        'drawer_board_thickness' => 15.0,
        'drawer_bottom_thickness' => 6.0,
        'drawer_bottom' => 'groove',
        'drawer_joint' => 'butt',
        'metal_thickness' => 13.0,
        'rail_height' => 90.0,
        'edge_thick' => 1.0,
        'edge_thin' => 0.4
      }.freeze
      ENUMS = {
        'cabinet_type' => %w[base wall tall],
        'back_mode' => %w[groove rabbet nailed],
        'base_type' => %w[plinth legs none],
        'top_type' => %w[full rails],
        'carcass_joint' => %w[confirmat minifix dowel dado],
        'shelf_type' => %w[adjustable fixed],
        'door_mode' => %w[auto single double none],
        'door_fit' => %w[full_overlay half_overlay inset],
        'front_style' => Calculator::ENUMS['front_style'],
        'handle' => Calculator::ENUMS['handle'],
        'pull_edge' => %w[auto top bottom side],
        'drawer_type' => Calculator::ENUMS['drawer_type'],
        'slide_type' => Calculator::ENUMS['slide_type'],
        'drawer_bottom' => Calculator::ENUMS['drawer_bottom'],
        'drawer_joint' => Calculator::ENUMS['drawer_joint']
      }.freeze
      STRINGS = %w[name columns bay_fronts].freeze
      JOINT_NAMES = {
        'confirmat' => 'Confirmat 7x50',
        'minifix' => 'Minifix ø15 + baut',
        'dowel' => 'Dowel ø8x30'
      }.freeze

      module_function

      def normalize(params)
        raise ArgumentError, 'Parameter kabinet harus berupa hash' unless params.nil? || params.is_a?(Hash)

        supplied = (params || {}).each_with_object({}) { |(key, value), result| result[key.to_s] = value }
        unknown = supplied.keys - DEFAULTS.keys
        raise ArgumentError, "Parameter kabinet tidak dikenal: #{unknown.first}" unless unknown.empty?

        p = DEFAULTS.merge(supplied)
        DEFAULTS.each do |key, default|
          if STRINGS.include?(key) || ENUMS.key?(key)
            p[key] = p[key].to_s.strip
          elsif key == 'shelves'
            p[key] = integer(p[key], key)
          else
            p[key] = number(p[key], key)
            raise ArgumentError, "#{key} tidak boleh negatif" if p[key].negative?
          end
        end
        ENUMS.each do |key, values|
          raise ArgumentError, "Nilai #{key} tidak valid: #{p[key]}" unless values.include?(p[key])
        end
        raise ArgumentError, 'Nama tidak boleh kosong' if p['name'].empty?
        raise ArgumentError, 'Kolom tidak boleh kosong' if p['columns'].empty?
        raise ArgumentError, 'Jumlah rak tidak boleh negatif' if p['shelves'].negative?

        %w[board_thickness back_thickness front_thickness drawer_board_thickness drawer_bottom_thickness].each do |key|
          raise ArgumentError, "#{key} harus lebih dari 0" unless p[key].positive?
        end
        if p['back_mode'] != 'nailed' && !(p['back_groove_depth'] > 1 && p['back_groove_depth'] < p['board_thickness'])
          raise ArgumentError, 'Kedalaman alur/sponing panel belakang harus > 1 mm dan < tebal papan'
        end
        if p['carcass_joint'] == 'dado' && !(p['dado_depth'] > 1 && p['dado_depth'] <= p['board_thickness'] / 2.0)
          raise ArgumentError, 'Kedalaman rumah (dado) harus > 1 mm dan maksimal setengah tebal papan'
        end
        raise ArgumentError, 'Lebar rail atas harus lebih dari 0' if p['top_type'] == 'rails' && !p['rail_width'].positive?
        if p['base_type'] != 'none' && p['plinth_height'] < 30
          raise ArgumentError, 'Tinggi plint/kaki minimal 30 mm (atau pilih tanpa alas)'
        end
        unless p['cup_distance'] >= 3 && p['cup_distance'] <= 7
          raise ArgumentError, 'Jarak bor cup engsel harus 3–7 mm dari tepi pintu'
        end
        unless p['hinge_angle'] >= 30 && p['hinge_angle'] <= 170
          raise ArgumentError, 'Sudut buka engsel harus 30–170°'
        end
        if p['handle'] == 'gola' && pull_edge(p) != 'top'
          raise ArgumentError, 'Gola hanya untuk tepi atas (kabinet bawah atau pull_edge atas)'
        end
        Calculator.normalize(drawer_params(p))
        p
      end

      # Front/drawer settings in Calculator's parameter names.
      def drawer_params(p)
        {
          'name' => p['name'], 'gap' => p['gap'], 'front_thickness' => p['front_thickness'],
          'front_style' => p['front_style'], 'frame_width' => p['frame_width'],
          'panel_thickness' => p['panel_thickness'], 'handle' => p['handle'],
          'handle_length' => p['handle_length'], 'gola_gap' => p['gola_gap'],
          'drawer_type' => p['drawer_type'], 'slide_type' => p['slide_type'],
          'slide_clearance' => p['slide_clearance'], 'slide_length' => p['slide_length'],
          'board_thickness' => p['drawer_board_thickness'], 'bottom_thickness' => p['drawer_bottom_thickness'],
          'drawer_bottom' => p['drawer_bottom'], 'drawer_joint' => p['drawer_joint'],
          'metal_thickness' => p['metal_thickness'], 'rail_height' => p['rail_height'],
          'edge_thick' => p['edge_thick'], 'edge_thin' => p['edge_thin']
        }
      end

      def pull_edge(p)
        return p['pull_edge'] unless p['pull_edge'] == 'auto'

        { 'base' => 'top', 'wall' => 'bottom', 'tall' => 'side' }.fetch(p['cabinet_type'])
      end

      # Bay front tokens (comma separated, one per column, or one for all):
      # door | door1 | door2 | open | drawers:3 | drawers:1:1:2 (Indonesian aliases accepted).
      def bay_fronts(p, count)
        tokens = p['bay_fronts'].split(',').map(&:strip).reject(&:empty?)
        tokens = ['door'] if tokens.empty?
        tokens *= count if tokens.length == 1
        if tokens.length != count
          raise ArgumentError, "Isian muka per kolom (#{tokens.length}) harus sama dengan jumlah kolom (#{count})"
        end

        tokens.map do |token|
          case token.downcase
          when 'door', 'pintu' then door_entry(p['door_mode'])
          when 'door1', 'pintu1' then { type: 'door', leaves: 1 }
          when 'door2', 'pintu2' then { type: 'door', leaves: 2 }
          when 'open', 'terbuka' then { type: 'open' }
          when /\A(?:drawers?|laci)(?::(.+))?\z/
            spec = Regexp.last_match(1) || '3'
            Calculator.split_lengths(spec, 1000.0)
            { type: 'drawers', spec: spec }
          else
            raise ArgumentError, "Isian muka tidak dikenal: #{token} (pakai door, door1, door2, open, drawers:3)"
          end
        end
      end

      def door_entry(mode)
        case mode
        when 'none' then { type: 'open' }
        when 'single' then { type: 'door', leaves: 1 }
        when 'double' then { type: 'door', leaves: 2 }
        else { type: 'door', leaves: nil }
        end
      end

      # Returns {parts: fixed carcass/hardware, doors: [...], drawers: [...], openings: [...]}.
      # doors: {name:, parts:, hinge_x:, hinge_y:, hinge_z:, side:, angle:} - pivot on the
      # front face at the hinge edge. drawers: {name:, parts:, travel:}.
      def compute(space, params = {})
        p = normalize(params)
        dims = normalize_space(space)
        w = dims['width']
        d = dims['depth']
        h = dims['height']
        t = p['board_thickness']
        g = p['gap']
        ft = p['front_thickness']
        inset = p['door_fit'] == 'inset'
        gola = p['handle'] == 'gola'
        base_h = p['base_type'] == 'none' ? 0.0 : p['plinth_height']
        raise ArgumentError, 'Ruang terlalu kecil untuk kabinet' if w < 150 || d < 150 || h < 150
        raise ArgumentError, 'Tinggi badan kabinet terlalu kecil' if h - base_h < 2 * t + 80

        back = back_layout(p, d)
        interior_back = back[:interior_back]
        front_y = inset ? ft : 0.0
        raise ArgumentError, 'Kedalaman bagian dalam kabinet terlalu kecil' if interior_back - front_y < 120

        inner_width = w - 2 * t
        count = column_count(p['columns'])
        widths = Calculator.split_lengths(p['columns'], inner_width - (count - 1) * t)
        raise ArgumentError, 'Lebar kolom terlalu kecil (min 100 mm)' if widths.any? { |bw| bw < 100 }

        fronts = bay_fronts(p, count)
        bays = []
        x = t
        widths.each_with_index do |bw, i|
          bays << { index: i + 1, x0: x, x1: x + bw, width: bw, front: fronts[i],
                    left: i.zero? ? 'side' : 'divider', right: i == count - 1 ? 'side' : 'divider' }
          x += bw + t
        end

        ctx = { p: p, w: w, d: d, h: h, t: t, g: g, ft: ft, inset: inset, gola: gola, base_h: base_h,
                back: back, front_y: front_y, int_lo: base_h + t, int_hi: h - t,
                top_notch: gola && !inset, dp: Calculator.normalize(drawer_params(p)) }
        parts = carcass(ctx, bays)
        doors = []
        drawers = []
        openings = []
        bays.each do |bay|
          case bay[:front][:type]
          when 'door'
            parts.concat(shelves(ctx, bay))
            leaves = bay[:front][:leaves] || (front_x_range(ctx, bay).reduce(:-).abs > 600 ? 2 : 1)
            doors.concat(bay_doors(ctx, bay, leaves, count, parts))
            openings.concat(compartments(ctx, bay))
          when 'open'
            parts.concat(shelves(ctx, bay))
            openings.concat(compartments(ctx, bay))
          when 'drawers'
            drawers.concat(bay_drawers(ctx, bay, parts))
          end
        end
        parts.concat(gola_top(ctx, bays)) if gola
        { parts: parts, doors: doors, drawers: drawers, openings: openings }
      end

      def back_layout(p, d)
        bt = p['back_thickness']
        case p['back_mode']
        when 'groove'
          rear = d - p['back_inset']
          raise ArgumentError, 'Jarak panel belakang terlalu besar' if rear - bt < 150

          { mode: 'groove', y0: rear - bt, y1: rear, panel_depth: d, interior_back: rear - bt,
            into: p['back_groove_depth'] - 1.0 }
        when 'rabbet'
          { mode: 'rabbet', y0: d - bt, y1: d, panel_depth: d, interior_back: d - bt,
            into: p['back_groove_depth'] - 0.5 }
        else
          { mode: 'nailed', y0: d - bt, y1: d, panel_depth: d - bt, interior_back: d - bt, into: 0.0 }
        end
      end

      def column_count(spec)
        tokens = spec.to_s.split(/[:,\s]+/).reject(&:empty?)
        raise ArgumentError, 'Kolom kosong' if tokens.empty?

        if tokens.length == 1 && tokens[0] =~ /\A\d+\z/ && tokens[0].to_f <= Calculator::FIXED_THRESHOLD
          count = tokens[0].to_i
          raise ArgumentError, 'Jumlah kolom minimal 1' if count < 1

          count
        else
          tokens.length
        end
      end

      # Vertical panel (side/divider) with optional front notches [[z0, z1], ...].
      def vertical_panel(ctx, name, role, x, z0, z1, y1, notches = [])
        t = ctx[:t]
        e = ctx[:p]['edge_thick']
        height = z1 - z0
        unless notches.any?
          return Production.panel(name, role, x, 0.0, z0, t, y1, height, len_axis: 'z', band: { l1: e })
        end

        nd = Production::GOLA_DEPTH
        points = [[0.0, 0.0], [y1, 0.0], [y1, height]]
        notches.sort_by { |n| -n[1] }.each_with_index do |(lo, hi), i|
          lo -= z0
          hi -= z0
          points << [0.0, height] if i.zero? && hi < height - 1e-6
          points << [0.0, hi] if hi < height - 1e-6
          points.concat([[nd, hi], [nd, lo], [0.0, lo]])
        end
        Production.panel(name, role, x, 0.0, z0, t, y1, height, len_axis: 'z', band: { l1: e },
                         shape: 'profile', axis: 'x', profile: points)
      end

      def carcass(ctx, bays)
        p = ctx[:p]
        t = ctx[:t]
        w = ctx[:w]
        h = ctx[:h]
        base_h = ctx[:base_h]
        back = ctx[:back]
        e = p['edge_thick']
        name = p['name']
        jd = p['carcass_joint'] == 'dado' ? p['dado_depth'] : 0.0
        notch = ctx[:top_notch] ? [[h - p['gola_gap'], h]] : []
        top_y0 = ctx[:top_notch] ? Production::GOLA_DEPTH : 0.0
        side_depth = back[:mode] == 'nailed' ? back[:panel_depth] : ctx[:d]
        parts = []
        parts << vertical_panel(ctx, "#{name} - Side L", 'side', 0.0, base_h, h, side_depth, notch)
        parts << vertical_panel(ctx, "#{name} - Side R", 'side', w - t, base_h, h, side_depth, notch)

        pd = back[:panel_depth]
        horizontals = []
        horizontals << ["#{name} - Bottom", 'bottom', 0.0, pd, base_h]
        if p['top_type'] == 'rails'
          rw = p['rail_width']
          raise ArgumentError, 'Rail atas terlalu lebar untuk kedalaman kabinet' if top_y0 + 2 * rw > pd

          horizontals << ["#{name} - Top Rail Front", 'rail', top_y0, top_y0 + rw, h - t]
          horizontals << ["#{name} - Top Rail Back", 'rail', pd - rw, pd, h - t]
        else
          horizontals << ["#{name} - Top", 'top', top_y0, pd, h - t]
        end
        horizontals.each do |label, role, y0, y1, z|
          parts << Production.panel(label, role, t - jd, y0, z, w - 2 * t + 2 * jd, y1 - y0, t,
                                    len_axis: 'x', band: { l1: e })
          joints_between_sides(ctx, parts, label, y0, y1, z, z + t, role == 'bottom' ? :top : :bottom)
        end

        divider_depth = back[:interior_back]
        bays.each_cons(2) do |left, right|
          dx = left[:x1]
          parts << vertical_panel(ctx, "#{name} - Divider #{left[:index]}", 'divider', dx, base_h + t - jd,
                                  h - t + jd, divider_depth, notch.map { |lo, hi| [lo, [hi, h - t + jd].min] })
          z_joints(ctx, parts, "#{name} - Divider #{left[:index]}", dx, divider_depth)
        end

        parts << back_panel(ctx)
        parts.concat(base(ctx))
        if p['cabinet_type'] == 'wall'
          [[t, 'L'], [w - t - 60.0, 'R']].each do |hx, side|
            parts << Production.hardware("#{name} - Hanger #{side}", 'hanger', 'Gantungan kabinet atas (hanger)',
                                         hx, ctx[:back][:interior_back] - 50.0, h - t - 60.0, 60.0, 50.0, 60.0)
          end
        end
        parts
      end

      def back_panel(ctx)
        p = ctx[:p]
        t = ctx[:t]
        back = ctx[:back]
        into = back[:into]
        if back[:mode] == 'nailed'
          x0 = 1.0
          width = ctx[:w] - 2.0
          z0 = ctx[:base_h] + 1.0
          height = ctx[:h] - ctx[:base_h] - 2.0
        else
          x0 = t - into
          width = ctx[:w] - 2 * t + 2 * into
          z0 = ctx[:base_h] + t - into
          height = ctx[:h] - ctx[:base_h] - 2 * t + 2 * into
        end
        Production.panel("#{p['name']} - Back", 'back', x0, back[:y0], z0, width, p['back_thickness'], height,
                         len_axis: height >= width ? 'z' : 'x', material: 'back')
      end

      def base(ctx)
        p = ctx[:p]
        t = ctx[:t]
        w = ctx[:w]
        bh = ctx[:base_h]
        name = p['name']
        ps = p['plinth_setback']
        pd = ctx[:back][:panel_depth]
        return [] if p['base_type'] == 'none'

        parts = []
        raise ArgumentError, 'Plint terlalu mundur untuk kedalaman kabinet' if ps + 2 * t + 80 > pd

        parts << Production.panel("#{name} - Plinth Front", 'plinth', 0.0, ps, 0.0, w, t, bh,
                                  len_axis: 'x', band: { l1: p['edge_thin'] })
        if p['base_type'] == 'plinth'
          back_y = pd - 20.0 - t
          parts << Production.panel("#{name} - Plinth Back", 'plinth', 0.0, back_y, 0.0, w, t, bh, len_axis: 'x')
          [[0.0, 'L'], [w - t, 'R']].each do |px, side|
            parts << Production.panel("#{name} - Plinth Side #{side}", 'plinth', px, ps + t, 0.0, t,
                                      back_y - ps - t, bh, len_axis: 'y')
          end
        else
          extra = ((w - 120.0) / 600.0).floor
          xs = Array.new(extra + 2) { |i| 60.0 + i * (w - 120.0) / (extra + 1) }
          [ps + t + 30.0, pd - 60.0].each do |ly|
            xs.each_with_index do |lx, i|
              parts << Production.cylinder("#{name} - Leg #{i + 1}", 'leg', format('Kaki adjustable %.0f mm', bh),
                                           [lx, ly, 0.0], 'z', 40.0, bh)
            end
          end
        end
        parts
      end

      # Connectors for a horizontal panel held between the two outer sides.
      # face: which face of the horizontal panel is hidden-but-accessible (cam side).
      def joints_between_sides(ctx, parts, label, y0, y1, z0, z1, face)
        t = ctx[:t]
        [[t, 1, 'L'], [ctx[:w] - t, -1, 'R']].each do |x_face, dir, side|
          x_joint(ctx, parts, "#{label} #{side}", x_face, dir, y0, y1, z0, z1, face)
        end
      end

      def x_joint(ctx, parts, label, x_face, dir, y0, y1, z0, z1, face)
        type = ctx[:p]['carcass_joint']
        return if type == 'dado'

        t = ctx[:t]
        zc = (z0 + z1) / 2.0
        Production.connector_positions(y1 - y0).each_with_index do |offset, i|
          y = y0 + offset
          tag = "#{label} - #{JOINT_NAMES[type]} #{i + 1}"
          case type
          when 'confirmat'
            start = dir.positive? ? x_face - t : x_face + t - 50.0
            parts << Production.cylinder(tag, 'connector', 'Confirmat 7x50', [start, y, zc], 'x', 7.0, 50.0)
          when 'minifix'
            cam_x = x_face + dir * 24.0
            cam_z = face == :top ? z1 - 12.5 : z0
            parts << Production.cylinder("#{tag} cam", 'connector', 'Minifix ø15 + baut', [cam_x, y, cam_z], 'z',
                                         15.0, 12.5)
            bolt_start = dir.positive? ? x_face - 11.0 : x_face - 24.0
            parts << Production.cylinder("#{tag} baut", 'connector', 'Minifix ø15 + baut', [bolt_start, y, zc], 'x',
                                         6.0, 35.0, qty: 0)
            dowel_y = offset + 32.0 <= y1 - y0 - 10 ? y + 32.0 : y - 32.0
            parts << Production.cylinder("#{tag} dowel", 'connector', 'Dowel ø8x30', [x_face - 15.0, dowel_y, zc],
                                         'x', 8.0, 30.0) if dowel_y > y0 + 8
          else
            parts << Production.cylinder(tag, 'connector', 'Dowel ø8x30', [x_face - 15.0, y, zc], 'x', 8.0, 30.0)
          end
        end
      end

      # Divider fixed to the bottom and top panels (vertical connectors).
      def z_joints(ctx, parts, label, x0, depth)
        type = ctx[:p]['carcass_joint']
        return if type == 'dado'

        t = ctx[:t]
        xc = x0 + t / 2.0
        [[ctx[:int_lo], 1, 'bawah'], [ctx[:int_hi], -1, 'atas']].each do |z_face, dir, where|
          Production.connector_positions(depth).each_with_index do |offset, i|
            tag = "#{label} #{where} - #{JOINT_NAMES[type]} #{i + 1}"
            case type
            when 'confirmat'
              start = dir.positive? ? z_face - t : z_face + t - 50.0
              parts << Production.cylinder(tag, 'connector', 'Confirmat 7x50', [xc, offset, start], 'z', 7.0, 50.0)
            when 'minifix'
              cam_z = z_face + dir * 24.0
              parts << Production.cylinder("#{tag} cam", 'connector', 'Minifix ø15 + baut', [x0 - 0.5, offset, cam_z],
                                           'x', 15.0, 12.5)
              bolt_start = dir.positive? ? z_face - 11.0 : z_face - 24.0
              parts << Production.cylinder("#{tag} baut", 'connector', 'Minifix ø15 + baut', [xc, offset, bolt_start],
                                           'z', 6.0, 35.0, qty: 0)
            else
              parts << Production.cylinder(tag, 'connector', 'Dowel ø8x30', [xc, offset, z_face - 15.0], 'z', 8.0, 30.0)
            end
          end
        end
      end

      # Front coverage for a bay, per hinge fit. Returns [x_left, x_right].
      def front_x_range(ctx, bay)
        t = ctx[:t]
        g = ctx[:g]
        fit = ctx[:p]['door_fit']
        left = cover(fit, bay[:left], t)
        right = cover(fit, bay[:right], t)
        [bay[:x0] - left + g / 2.0, bay[:x1] + right - g / 2.0]
      end

      # How far a front reaches over the panel next to it (0 for inset).
      def cover(fit, panel, t)
        return 0.0 if fit == 'inset'
        return t / 2.0 if panel == 'divider' || fit == 'half_overlay'

        t
      end

      def front_z_range(ctx)
        t = ctx[:t]
        g = ctx[:g]
        fit = ctx[:p]['door_fit']
        lo = ctx[:base_h] + t - cover(fit, 'side', t)
        hi = ctx[:h] - t + cover(fit, 'side', t)
        [lo + g / 2.0, hi - g / 2.0]
      end

      def hinge_type(fit, panel)
        return 'inset' if fit == 'inset'
        return 'half_overlay' if panel == 'divider' || fit == 'half_overlay'

        'full_overlay'
      end

      def bay_doors(ctx, bay, leaves, bay_count, fixed)
        p = ctx[:p]
        g = ctx[:g]
        ft = ctx[:ft]
        x0, x1 = front_x_range(ctx, bay)
        z0, z1 = front_z_range(ctx)
        z1 -= p['gola_gap'] if ctx[:gola]
        fy = ctx[:inset] ? 0.0 : -ft
        width = leaves == 2 ? (x1 - x0 - g) / 2.0 : x1 - x0
        height = z1 - z0
        raise ArgumentError, "Kolom #{bay[:index]}: pintu terlalu kecil" if width < 100 || height < 150

        edge = pull_edge(p)
        Array.new(leaves) do |i|
          side = if leaves == 2
                   i.zero? ? 'left' : 'right'
                 else
                   bay_count > 1 && bay[:index] == bay_count ? 'right' : 'left'
                 end
          fx = x0 + i * (width + g)
          name = "#{p['name']} Bay #{bay[:index]} Door #{i + 1}"
          front_edge = edge == 'side' ? (side == 'left' ? 'right' : 'left') : edge
          parts = Calculator.front_parts(name, fx, fy, z0, width, height, ctx[:dp], pull_edge: front_edge, grain: 'z')
          front = { x: fx, y: fy, z: z0, w: width, h: height }
          parts.concat(Calculator.pull_parts(name, front, ctx[:dp], kind: :door, hinge_side: side,
                                             pull_edge: edge == 'side' ? 'side' : edge))
          panel = side == 'left' ? bay[:left] : bay[:right]
          hinges(ctx, bay, name, front, side, hinge_type(p['door_fit'], panel), parts, fixed)
          { name: name, parts: parts, side: side, angle: p['hinge_angle'],
            hinge_x: side == 'left' ? fx : fx + width, hinge_y: fy, hinge_z: z0 }
        end
      end

      # Cup (moves with the door), arm + mounting plate (stay on the carcass).
      def hinges(ctx, bay, name, front, side, type, door_parts, fixed)
        p = ctx[:p]
        ft = ctx[:ft]
        back_face = front[:y] + ft
        offset = p['cup_distance'] + Production::CUP_DIAMETER / 2.0
        cx = side == 'left' ? front[:x] + offset : front[:x] + front[:w] - offset
        face_x = side == 'left' ? bay[:x0] : bay[:x1]
        plate_x = side == 'left' ? face_x : face_x - 10.0
        plate_y = Production::SYSTEM_LINE + (ctx[:inset] ? ft : 0.0)
        desc = Production::HINGE_NAMES.fetch(type)
        Production.hinge_positions(front[:h]).each_with_index do |pos, i|
          cz = front[:z] + pos
          door_parts << Production.cylinder("#{name} - Hinge cup #{i + 1}", 'hinge', desc,
                                            [cx, back_face - 12.5, cz], 'y', Production::CUP_DIAMETER,
                                            Production::CUP_DEPTH)
          fixed << Production.hardware("#{name} - Mounting plate #{i + 1}", 'hinge_plate', 'Mounting plate 0 mm',
                                       plate_x, plate_y - 22.0, cz - 16.0, 10.0, 44.0, 32.0)
          inner = side == 'left' ? plate_x + 10.0 : plate_x
          ax0 = [cx, inner].min
          ax1 = [[cx, inner].max, ax0 + 10.0].max
          ay0 = back_face + 0.5
          ay1 = [plate_y - 22.0, ay0 + 5.0].max
          fixed << Production.hardware("#{name} - Hinge arm #{i + 1}", 'hinge', desc, ax0, ay0, cz - 7.0,
                                       ax1 - ax0, ay1 - ay0, 14.0, qty: 0)
        end
      end

      def shelf_levels(ctx)
        count = ctx[:p]['shelves']
        return [] if count.zero?

        t = ctx[:t]
        clear = (ctx[:int_hi] - ctx[:int_lo]) - count * t
        raise ArgumentError, 'Rak tidak muat dalam tinggi kabinet' if clear / (count + 1.0) < 60

        gap = clear / (count + 1.0)
        Array.new(count) { |i| ctx[:int_lo] + gap * (i + 1) + t * i }
      end

      def shelves(ctx, bay)
        p = ctx[:p]
        t = ctx[:t]
        e = p['edge_thick']
        parts = []
        fixed = p['shelf_type'] == 'fixed'
        y0 = ctx[:front_y] + p['shelf_setback']
        y1 = ctx[:back][:interior_back] - (fixed ? 0.0 : 2.0)
        raise ArgumentError, 'Setback rak terlalu besar' if y1 - y0 < 80

        jd = p['carcass_joint'] == 'dado' && fixed ? p['dado_depth'] : 0.0
        shelf_levels(ctx).each_with_index do |z, i|
          label = "#{p['name']} - Bay #{bay[:index]} Shelf #{i + 1}"
          if fixed
            parts << Production.panel(label, 'shelf', bay[:x0] - jd, y0, z, bay[:width] + 2 * jd, y1 - y0, t,
                                      len_axis: 'x', band: { l1: e })
            x_joint(ctx, parts, "#{label} L", bay[:x0], 1, y0, y1, z, z + t, :bottom)
            x_joint(ctx, parts, "#{label} R", bay[:x1], -1, y0, y1, z, z + t, :bottom)
          else
            parts << Production.panel(label, 'shelf', bay[:x0] + 1.0, y0, z, bay[:width] - 2.0, y1 - y0, t,
                                      len_axis: 'x', band: { l1: e })
            [y0 + Production::SYSTEM_LINE, y1 - Production::SYSTEM_LINE].each do |py|
              parts << Production.cylinder("#{label} - Pin L", 'shelf_pin', 'Pen rak ø5', [bay[:x0] - 8.0, py, z - 3.0],
                                           'x', 5.0, 12.0)
              parts << Production.cylinder("#{label} - Pin R", 'shelf_pin', 'Pen rak ø5', [bay[:x1] - 4.0, py, z - 3.0],
                                           'x', 5.0, 12.0)
            end
          end
        end
        parts
      end

      # Usable compartments of door/open bays for "Insert Drawers".
      def compartments(ctx, bay)
        levels = shelf_levels(ctx)
        t = ctx[:t]
        bounds = [ctx[:int_lo]] + levels.flat_map { |z| [z, z + t] } + [ctx[:int_hi]]
        y0 = ctx[:front_y]
        bounds.each_slice(2).with_index.map do |(low, high), index|
          { 'name' => "Bay #{bay[:index]} / Space #{index + 1}",
            'origin' => [bay[:x0], y0, low],
            'space' => { 'width' => bay[:width], 'depth' => ctx[:back][:interior_back] - y0, 'height' => high - low } }
        end
      end

      def bay_drawers(ctx, bay, fixed)
        p = ctx[:p]
        g = ctx[:g]
        x0, x1 = front_x_range(ctx, bay)
        z0, z1 = front_z_range(ctx)
        env_lo = z0 - g / 2.0
        env_hi = z1 + g / 2.0
        heights = Calculator.split_lengths(bay[:front][:spec], env_hi - env_lo).reverse
        gola_gap = ctx[:gola] ? p['gola_gap'] : 0.0
        fy = ctx[:inset] ? 0.0 : -ctx[:ft]
        count = heights.length
        z = env_lo
        heights.each_with_index.map do |cell_h, i|
          cell_lo = z
          cell_hi = z + cell_h
          z = cell_hi
          top = i == count - 1
          name = "#{p['name']} Bay #{bay[:index]} Drawer #{count - i}"
          front = { x: x0, y: fy, z: cell_lo + g / 2.0, w: x1 - x0, h: cell_h - g - gola_gap,
                    box_y: ctx[:front_y] }
          raise ArgumentError, "#{name}: muka laci terlalu kecil" if front[:h] < 60

          lo = [cell_lo, ctx[:int_lo]].max
          hi = [cell_hi - gola_gap, ctx[:int_hi]].min
          opening = { 'x' => bay[:x0], 'z' => lo, 'width' => bay[:width], 'height' => hi - lo,
                      'depth' => ctx[:back][:interior_back] }
          gola = if ctx[:gola] && !top
                   { kind: 'C', x: bay[:x0], width: bay[:width], z: front[:z] + front[:h] + g / 2.0,
                     height: gola_gap }
                 end
          unit = Calculator.drawer_unit(name, front, opening, ctx[:dp], gola: gola)
          fixed.concat(unit[:fixed])
          { name: name, parts: unit[:moving], travel: unit[:travel] }
        end
      end

      # Top L profile: full width in the side notches (overlay) or per bay (inset).
      def gola_top(ctx, bays)
        p = ctx[:p]
        height = p['gola_gap']
        section = Profiles.gola_section('L', height)
        spans = if ctx[:top_notch]
                  [[0.0, ctx[:w], ctx[:h] - height]]
                else
                  z = front_z_range(ctx)[1] - height + ctx[:g] / 2.0
                  bays.map { |bay| [bay[:x0], bay[:width], z] }
                end
        spans.each_with_index.map do |(x, width, z), i|
          Production.hardware("#{p['name']} - Profil gola L #{i + 1}", 'gola', 'Profil gola L aluminium', x, 0.0, z,
                              width, Production::GOLA_DEPTH, height, shape: 'profile', axis: 'x', profile: section,
                              length: width, material: 'aluminium')
        end
      end

      def normalize_space(space)
        raise ArgumentError, 'Ukuran kabinet tidak valid' unless space.is_a?(Hash)

        normalized = space.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
        %w[width depth height].each_with_object({}) do |key, result|
          raise ArgumentError, "Ukuran #{key} belum diisi" unless normalized.key?(key)

          result[key] = number(normalized[key], key)
          raise ArgumentError, "Ukuran #{key} harus lebih dari 0" unless result[key].positive?
        end
      end

      def number(value, name)
        result = Float(value)
        raise ArgumentError, "#{name} harus berupa angka" unless result.finite?

        result
      rescue TypeError, ArgumentError
        raise ArgumentError, "#{name} harus berupa angka"
      end

      def integer(value, name)
        result = Integer(value)
        raise ArgumentError, "#{name} harus bilangan bulat" if value.is_a?(Float) && result != value

        result
      rescue TypeError, ArgumentError
        raise ArgumentError, "#{name} harus bilangan bulat"
      end
    end
  end
end
