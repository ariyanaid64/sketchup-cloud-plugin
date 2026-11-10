# Pure-Ruby cabinet geometry. All dimensions and coordinates are millimetres.
# The space origin is the inside front-bottom-left corner of the cabinet.
require_relative 'calculator' unless defined?(SketchupCloud::DrawerMakerPro::Calculator)

module SketchupCloud
  module DrawerMakerPro
    module CabinetCalculator
      DEFAULTS = {
        'name' => 'Cabinet',
        'board_thickness' => 18.0,
        'back_thickness' => 6.0,
        'plinth_height' => 100.0,
        'columns' => '2',
        'shelves' => 1,
        'door_mode' => 'double',
        'front_style' => 'shaker',
        'front_thickness' => 18.0,
        'frame_width' => 60.0,
        'panel_thickness' => 6.0,
        'gap' => 3.0,
        'handle' => 'bar',
        'handle_length' => 128.0
      }.freeze

      module_function

      def normalize(params)
        raise ArgumentError, 'Cabinet parameters must be a hash' unless params.is_a?(Hash)

        supplied = params.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
        unknown = supplied.keys - DEFAULTS.keys
        raise ArgumentError, "Unknown cabinet parameter: #{unknown.first}" unless unknown.empty?

        p = DEFAULTS.merge(supplied)
        %w[name columns door_mode front_style handle].each do |key|
          p[key] = p[key].to_s
        end
        %w[board_thickness back_thickness plinth_height front_thickness frame_width panel_thickness gap handle_length].each do |key|
          p[key] = number(p[key], key)
        end
        p['shelves'] = integer(p['shelves'], 'shelves')
        raise ArgumentError, 'Name must not be empty' if p['name'].strip.empty?
        raise ArgumentError, 'Columns must not be empty' if p['columns'].strip.empty?
        raise ArgumentError, 'Door mode must be none, single or double' unless %w[none single double].include?(p['door_mode'])
        raise ArgumentError, 'Front style must be slab, shaker or glass' unless %w[slab shaker glass].include?(p['front_style'])
        raise ArgumentError, 'Handle must be bar or none' unless %w[bar none].include?(p['handle'])
        raise ArgumentError, 'Shelves must be non-negative' if p['shelves'].negative?

        positive = %w[board_thickness back_thickness front_thickness frame_width panel_thickness handle_length]
        positive.each { |key| raise ArgumentError, "#{key} must be greater than 0" unless p[key].positive? }
        %w[plinth_height gap].each { |key| raise ArgumentError, "#{key} must not be negative" if p[key].negative? }
        if %w[shaker glass].include?(p['front_style']) && p['panel_thickness'] > p['front_thickness']
          raise ArgumentError, 'Panel thickness cannot exceed front thickness'
        end
        p
      end

      # Returns carcass parts, door part groups, and bay spaces in local space
      # coordinates. Each opening's origin is its front-bottom-left corner.
      def compute(space, params = {})
        p = normalize(params)
        dimensions = normalize_space(space)
        w = dimensions['width']
        d = dimensions['depth']
        h = dimensions['height']
        t = p['board_thickness']
        bt = p['back_thickness']
        ph = p['plinth_height']
        gap = p['gap']
        raise ArgumentError, 'Space is too small for a cabinet' if w < 50 || d < 50 || h < 50
        raise ArgumentError, 'Cabinet boards do not fit the space' if w <= 2 * t || d <= bt || h <= ph + 2 * t
        raise ArgumentError, 'Front thickness exceeds cabinet depth' if p['front_thickness'] >= d - bt
        raise ArgumentError, 'Plinth must be shorter than the cabinet height' if ph >= h - t

        inner_width = w - 2 * t
        column_count = Calculator.split_lengths(p['columns'], inner_width).length
        column_widths = Calculator.split_lengths(p['columns'], inner_width - (column_count - 1) * t)
        if column_widths.any? { |width| width < 30 || (p['door_mode'] != 'none' && width <= gap) }
          raise ArgumentError, 'A cabinet bay is too small for a front'
        end

        open_height = h - ph - 2 * t
        if open_height < 30 || (p['door_mode'] != 'none' && open_height <= gap)
          raise ArgumentError, 'Cabinet opening is too small'
        end
        shelf_clear_height = open_height - p['shelves'] * t
        raise ArgumentError, 'Shelves do not fit the cabinet height' if shelf_clear_height <= 0
        usable_depth = d - bt - p['front_thickness']
        raise ArgumentError, 'Cabinet opening depth is too small' if usable_depth < 30

        parts = carcass_parts(w, d, h, p, column_widths, usable_depth)
        openings = []
        doors = []
        bay_x = t
        column_widths.each_with_index do |bay_width, bay_index|
          opening = {
            'index' => bay_index + 1,
            'name' => "#{p['name']} Bay #{bay_index + 1}",
            'origin' => [bay_x, p['front_thickness'], ph + t],
            'space' => { 'width' => bay_width, 'depth' => usable_depth, 'height' => open_height }
          }
          openings << opening
          doors.concat(door_parts(opening, p, bay_index + 1)) unless p['door_mode'] == 'none'
          bay_x += bay_width + t
        end

        { parts: parts, doors: doors, openings: openings }
      end

      def carcass_parts(width, depth, height, p, column_widths, usable_depth)
        t = p['board_thickness']
        back_t = p['back_thickness']
        plinth = p['plinth_height']
        inner_width = width - 2 * t
        carcass_depth = depth - back_t
        parts = [
          Part.new("#{p['name']} - Side L", 'side', 0.0, 0.0, plinth, t, depth, height - plinth),
          Part.new("#{p['name']} - Side R", 'side', width - t, 0.0, plinth, t, depth, height - plinth),
          Part.new("#{p['name']} - Floor", 'bottom', t, 0.0, plinth, inner_width, carcass_depth, t),
          Part.new("#{p['name']} - Top", 'top', t, 0.0, height - t, inner_width, carcass_depth, t),
          Part.new("#{p['name']} - Back", 'back', t, depth - back_t, plinth, inner_width, back_t, height - plinth),
          Part.new("#{p['name']} - Plinth", 'plinth', t, [50.0, carcass_depth - t].min, 0.0, inner_width, t, plinth)
        ]

        bay_x = t
        column_widths.each_with_index do |bay_width, index|
          if index.positive?
            parts << Part.new("#{p['name']} - Divider #{index}", 'divider', bay_x, p['front_thickness'],
                              plinth + t, t, usable_depth, height - plinth - 2 * t)
            bay_x += t
          end
          parts.concat(shelf_parts(p, bay_x, bay_width, usable_depth, plinth + t,
                                   height - plinth - t, index + 1))
          bay_x += bay_width
        end
        parts
      end

      def shelf_parts(p, x, width, depth, bottom, top, bay_index)
        count = p['shelves']
        return [] if count.zero?

        thickness = p['board_thickness']
        clear = (top - bottom) - count * thickness
        gap = clear / (count + 1.0)
        Array.new(count) do |index|
          z = bottom + gap * (index + 1) + thickness * index
          Part.new("#{p['name']} - Bay #{bay_index} Shelf #{index + 1}", 'shelf',
                   x, p['front_thickness'], z, width, depth, thickness)
        end
      end

      def door_parts(opening, p, bay_index)
        origin = opening['origin']
        space = opening['space']
        x = origin[0]
        z = origin[2]
        width = space['width']
        height = space['height']
        count = p['door_mode'] == 'double' ? 2 : 1
        door_width = count == 1 ? width - p['gap'] : (width - 2 * p['gap']) / 2.0
        raise ArgumentError, "Bay #{bay_index}: door is too small" if door_width < 30 || height - p['gap'] < 30

        Array.new(count) do |index|
          left = count == 1 || index.zero?
          door_x = count == 1 ? x + p['gap'] / 2.0 : x + p['gap'] / 2.0 + index * (door_width + p['gap'])
          side = if count == 1
                   'left'
                 else
                   left ? 'left' : 'right'
                 end
          door_name = "#{p['name']} Bay #{bay_index} Door #{index + 1}"
          parts = if Calculator.respond_to?(:front_parts)
                    Calculator.front_parts(door_name, door_x, 0.0, z + p['gap'] / 2.0,
                                           door_width, height - p['gap'], p)
                  else
                    [Part.new("#{door_name} - Front", 'front', door_x, 0.0,
                              z + p['gap'] / 2.0, door_width, p['front_thickness'], height - p['gap'])]
                  end
          hinge_x = side == 'left' ? door_x : door_x + door_width
          door = {
            name: door_name,
            parts: parts,
            hinge_x: hinge_x,
            hinge_z: z + p['gap'] / 2.0,
            side: side
          }
          add_handle(door, door_x, z + p['gap'] / 2.0, door_width, height - p['gap'], p) if p['handle'] == 'bar'
          door
        end
      end

      def add_handle(door, x, z, width, height, p)
        length = [p['handle_length'], height - 40.0].min
        raise ArgumentError, "#{door[:name]}: door is too small for a handle" if length < 30

        handle_x = door[:side] == 'left' ? x + width - 38.0 : x + 26.0
        door[:parts] << Part.new("#{door[:name]} - Handle", 'handle', handle_x, -30.0,
                                 z + (height - length) / 2.0, 12.0, 30.0, length)
      end

      def normalize_space(space)
        raise ArgumentError, 'Space must be a hash' unless space.is_a?(Hash)

        normalized = space.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
        %w[width depth height].each_with_object({}) do |key, result|
          raise ArgumentError, "Space is missing #{key}" unless normalized.key?(key)
          result[key] = number(normalized[key], key)
          raise ArgumentError, "Space #{key} must be greater than 0" unless result[key].positive?
        end
      end

      def number(value, name)
        result = Float(value)
        raise ArgumentError, "#{name} must be finite" unless result.finite?
        result
      rescue TypeError, ArgumentError
        raise ArgumentError, "#{name} must be a finite number"
      end

      def integer(value, name)
        result = Integer(value)
        raise ArgumentError, "#{name} must be an integer" if value.is_a?(Float) && result != value
        result
      rescue TypeError, ArgumentError
        raise ArgumentError, "#{name} must be an integer"
      end
    end
  end
end
