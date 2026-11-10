require 'json'

module SketchupCloud
  module DrawerMakerPro
    # Turns Calculator output into SketchUp geometry.
    module Builder
      DICT = 'DrawerMakerPro'.freeze

      COLORS = {
        'front'     => ['DMP Front',  Sketchup::Color.new(232, 226, 214)],
        'side'      => ['DMP Box',    Sketchup::Color.new(196, 160, 112)],
        'sub_front' => ['DMP Box',    Sketchup::Color.new(196, 160, 112)],
        'back'      => ['DMP Box',    Sketchup::Color.new(196, 160, 112)],
        'bottom'    => ['DMP Bottom', Sketchup::Color.new(170, 140, 100)],
        'handle'    => ['DMP Handle', Sketchup::Color.new(60, 60, 60)]
      }.freeze

      module_function

      def drawer_set?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(DICT, 'type') == 'set'
      end

      # entities: where the set is created; transformation: places the space
      # origin (front-bottom-left) in those entities' coordinates.
      def create(entities, transformation, space, params)
        drawers = Calculator.compute(space, params)
        model = Sketchup.active_model
        model.start_operation('Insert Drawers', true)
        begin
          set = entities.add_group
          set.transformation = transformation
          fill(set, space, params, drawers)
          model.commit_operation
          set
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def rebuild(set, params)
        space = JSON.parse(set.get_attribute(DICT, 'space'))
        drawers = Calculator.compute(space, params)
        model = Sketchup.active_model
        model.start_operation('Edit Drawers', true)
        begin
          set.entities.clear!
          fill(set, space, params, drawers)
          model.commit_operation
          set
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def fill(set, space, params, drawers)
        p = Calculator.normalize(params)
        set.name = "#{p['name']} set (#{drawers.size})"
        set.set_attribute(DICT, 'type', 'set')
        set.set_attribute(DICT, 'space', JSON.generate(space))
        set.set_attribute(DICT, 'params', JSON.generate(p))

        drawers.each do |drawer|
          dg = set.entities.add_group
          dg.name = "#{p['name']} #{drawer[:index]}"
          dg.set_attribute(DICT, 'type', 'drawer')
          drawer[:parts].each { |part| add_part(dg.entities, part, p['name']) }
        end
      end

      def add_part(entities, part, set_name)
        g = entities.add_group
        g.name = part.name
        x = part.x.mm
        y = part.y.mm
        z = part.z.mm
        pts = [[x, y, z], [x + part.dx.mm, y, z], [x + part.dx.mm, y + part.dy.mm, z], [x, y + part.dy.mm, z]]
        face = g.entities.add_face(pts)
        face.reverse! if face.normal.z < 0
        face.pushpull(part.dz.mm)
        g.material = material_for(part.role)

        cut = part.cut_size
        g.set_attribute(DICT, 'type', 'part')
        g.set_attribute(DICT, 'set', set_name)
        g.set_attribute(DICT, 'role', part.role)
        g.set_attribute(DICT, 'length', cut[:length].round(1))
        g.set_attribute(DICT, 'width', cut[:width].round(1))
        g.set_attribute(DICT, 'thickness', cut[:thickness].round(1))
        g
      end

      def material_for(role)
        name, color = COLORS[role] || COLORS['side']
        materials = Sketchup.active_model.materials
        materials[name] || materials.add(name).tap { |m| m.color = color }
      end
    end
  end
end
