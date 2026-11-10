# Production rules shared by the drawer and cabinet calculators. Pure Ruby,
# millimetres. Values are common frameless (32 mm system) workshop defaults,
# not a specific vendor's specification.
module SketchupCloud
  module DrawerMakerPro
    # shape: nil = box, 'profile' = extruded cross-section, 'cylinder'.
    # axis: extrusion / cylinder axis ('x', 'y' or 'z').
    # profile: [[u, v], ...] relative to the part origin, in the plane normal to
    # axis: axis x => (y, z), axis y => (x, z), axis z => (x, y).
    # info: :kind ('panel' | 'hardware') plus cut-list / BOM data.
    Part = Struct.new(:name, :role, :x, :y, :z, :dx, :dy, :dz, :shape, :axis, :profile, :info) do
      def cut_size
        dims = [dx, dy, dz].sort
        { length: dims[2], width: dims[1], thickness: dims[0] }
      end

      def kind
        (info && info[:kind]) || 'panel'
      end

      def hardware?
        kind == 'hardware'
      end

      def to_h
        { name: name, role: role, x: x, y: y, z: z, dx: dx, dy: dy, dz: dz,
          kind: kind, shape: shape || 'box' }.merge(cut_size)
      end
    end

    module Production
      SLIDE_LENGTHS = (250..650).step(50).map(&:to_f).freeze
      SLIDE_CLEARANCE = { 'ball_bearing' => 12.7, 'roller' => 12.5, 'undermount' => 5.0 }.freeze
      SLIDE_NAMES = {
        'ball_bearing' => 'Rel ball bearing full extension',
        'roller' => 'Rel roller/epoxy 3/4 extension',
        'undermount' => 'Rel undermount soft-close full extension',
        'custom' => 'Rel laci (custom)'
      }.freeze
      UNDERMOUNT_RECESS = 13.0
      CUP_DIAMETER = 35.0
      CUP_DEPTH = 13.0
      SYSTEM_LINE = 37.0
      HINGE_EDGE = 100.0
      GOLA_DEPTH = 27.0
      EDGE_PROFILE_HEIGHT = 20.0
      HINGE_NAMES = {
        'full_overlay' => 'Engsel sendok 35 mm full overlay (lurus / crank 0)',
        'half_overlay' => 'Engsel sendok 35 mm half overlay (crank 9,5)',
        'inset' => 'Engsel sendok 35 mm inset (crank 18)'
      }.freeze

      module_function

      # Common hinge-count guide by door height (lighter doors).
      def hinge_count(height)
        return 2 if height <= 900
        return 3 if height <= 1600
        return 4 if height <= 2000

        5
      end

      # Cup centres measured from the door's bottom edge.
      def hinge_positions(height)
        count = hinge_count(height)
        edge = [HINGE_EDGE, height / 4.0].min
        step = (height - 2 * edge) / (count - 1)
        Array.new(count) { |i| edge + i * step }
      end

      # Connector positions along a joint: 50 mm from each edge, max 300 mm apart.
      def connector_positions(length, edge = 50.0, spacing = 300.0)
        return [length / 2.0] if length < 2 * edge + 20

        count = [((length - 2 * edge) / spacing).ceil + 1, 2].max
        step = (length - 2 * edge) / (count - 1)
        Array.new(count) { |i| edge + i * step }
      end

      # Nominal slide length: the requested size, or the longest standard length that fits.
      def slide_length(available, requested)
        if requested.positive?
          if requested > available + 1e-6
            raise ArgumentError, format('Rel %.0f mm tidak muat (kedalaman tersedia %.0f mm)', requested, available)
          end

          return requested
        end
        fit = SLIDE_LENGTHS.select { |length| length <= available + 1e-6 }.max
        unless fit
          raise ArgumentError, format('Kedalaman %.0f mm kurang untuk rel standar terpendek 250 mm', available)
        end

        fit
      end

      def check_dims!(name, dims)
        dims.each do |dim|
          unless dim.is_a?(Numeric) && dim.finite? && dim.positive?
            raise ArgumentError, "#{name}: ukuran hasil harus lebih dari 0 (cek parameter)"
          end
        end
      end

      # Edge keys: for the given length axis, l1/l2 are the edges running along
      # the length (they reduce the cut width), w1/w2 the short edges.
      def panel(name, role, x, y, z, dx, dy, dz, len_axis:, band: {}, material: 'carcass',
                shape: nil, axis: nil, profile: nil)
        check_dims!(name, [dx, dy, dz])
        info = { kind: 'panel', material: material, len_axis: len_axis }
        info.merge!(panel_sizes(dx.to_f, dy.to_f, dz.to_f, len_axis, band))
        Part.new(name, role, x.to_f, y.to_f, z.to_f, dx.to_f, dy.to_f, dz.to_f, shape, axis, profile, info)
      end

      def panel_sizes(dx, dy, dz, len_axis, band)
        dims = { 'x' => dx, 'y' => dy, 'z' => dz }
        t_axis = (dims.keys - [len_axis]).min_by { |key| dims[key] }
        w_axis = (dims.keys - [len_axis, t_axis]).first
        b = { l1: 0.0, l2: 0.0, w1: 0.0, w2: 0.0 }
        band.each { |key, value| b[key.to_sym] = value.to_f }
        length = dims[len_axis]
        width = dims[w_axis]
        { finish_l: length, finish_w: width, thickness: dims[t_axis],
          cut_l: length - b[:w1] - b[:w2], cut_w: width - b[:l1] - b[:l2], band: b }
      end

      def hardware(name, role, desc, x, y, z, dx, dy, dz, shape: nil, axis: nil, profile: nil,
                   qty: 1, length: nil, material: 'metal')
        check_dims!(name, [dx, dy, dz])
        info = { kind: 'hardware', desc: desc, qty: qty, length: length, material: material }
        Part.new(name, role, x.to_f, y.to_f, z.to_f, dx.to_f, dy.to_f, dz.to_f, shape, axis, profile, info)
      end

      def cylinder(name, role, desc, center, axis, diameter, length, qty: 1, material: 'metal')
        cx, cy, cz = center
        r = diameter / 2.0
        case axis
        when 'x' then hardware(name, role, desc, cx, cy - r, cz - r, length, diameter, diameter,
                               shape: 'cylinder', axis: 'x', qty: qty, material: material)
        when 'y' then hardware(name, role, desc, cx - r, cy, cz - r, diameter, length, diameter,
                               shape: 'cylinder', axis: 'y', qty: qty, material: material)
        else hardware(name, role, desc, cx - r, cy - r, cz, diameter, diameter, length,
                      shape: 'cylinder', axis: 'z', qty: qty, material: material)
        end
      end
    end

    # 2D cross-sections for handleless fronts and aluminium profiles.
    # Section coordinates (u, v): u = depth from the front face (0 = visible face),
    # v = distance along the front towards the pull edge (pull edge at v = size).
    module Profiles
      module_function

      def front_section(type, ft, size)
        case type
        when 'j_pull'
          lip = [5.0, ft / 3.0].min
          radius = ft - lip
          depth = [25.0, radius + 6.0].max
          raise ArgumentError, 'Muka terlalu kecil untuk profil J-pull' if depth > size - 20
          centre = size - depth + radius
          arc = (0..8).map do |i|
            angle = -Math::PI / 2 - i * (Math::PI / 2) / 8
            [ft + radius * Math.cos(angle), centre + radius * Math.sin(angle)]
          end
          [[0.0, 0.0], [ft, 0.0]] + arc + [[lip, size], [0.0, size]]
        when 'shark_tooth'
          lip = [3.0, ft / 4.0].min
          raise ArgumentError, 'Muka terlalu kecil untuk profil shark tooth' if ft - lip > size - 20
          [[0.0, 0.0], [ft, 0.0], [ft, size - (ft - lip)], [lip, size], [0.0, size]]
        else
          raise ArgumentError, "Profil muka tidak dikenal: #{type}"
        end
      end

      # Aluminium edge pull mounted on the pull edge; v = 0 sits on the front edge.
      def edge_profile_section(ft, height = Production::EDGE_PROFILE_HEIGHT)
        [[0.0, 0.0], [ft, 0.0], [ft, height - 8], [ft + 8, height - 8], [ft + 8, height - 6],
         [ft - 2, height - 6], [ft - 2, 2.0], [2.0, 2.0], [2.0, height], [0.0, height]]
      end

      # Gola channel; u = depth behind the carcass front plane, v = height.
      def gola_section(kind, height, depth = Production::GOLA_DEPTH)
        wall = 1.5
        if kind == 'L'
          [[0.0, 0.0], [depth, 0.0], [depth, height], [depth - wall, height], [depth - wall, wall], [0.0, wall]]
        else
          [[0.0, 0.0], [depth, 0.0], [depth, height], [0.0, height], [0.0, height - wall],
           [depth - wall, height - wall], [depth - wall, wall], [0.0, wall]]
        end
      end

      # Maps a pull-edge section onto a front box (width w, height h, thickness ft).
      # Returns [axis, points] in builder profile coordinates.
      def place(section, edge, w, h)
        case edge
        when 'top' then ['x', section.map { |u, v| [u, v] }]
        when 'bottom' then ['x', section.map { |u, v| [u, h - v] }]
        when 'right' then ['z', section.map { |u, v| [v, u] }]
        when 'left' then ['z', section.map { |u, v| [w - v, u] }]
        else raise ArgumentError, "Tepi pegangan tidak dikenal: #{edge}"
        end
      end
    end
  end
end
