require 'json'

module SketchupCloud
  module DrawerMakerPro
    # Turns calculator parts into SketchUp geometry. Panels are unique groups;
    # identical hardware shares one component definition. Each door / drawer is
    # a Dynamic Component (wrapper + moving child with onClick ANIMATE) so the
    # Interact tool opens and closes it.
    module Builder
      DICT = 'DrawerMakerPro'.freeze
      DC = 'dynamic_attributes'.freeze

      MATERIALS = {
        'carcass' => ['DMP Carcass', [236, 229, 215]],
        'back' => ['DMP Back', [214, 200, 176]],
        'front' => ['DMP Front', [192, 153, 108]],
        'drawer_box' => ['DMP Drawer Box', [224, 198, 152]],
        'drawer_bottom' => ['DMP Drawer Bottom', [201, 178, 137]],
        'glass' => ['DMP Glass', [158, 206, 214], 0.35],
        'metal' => ['DMP Metal', [150, 156, 163]],
        'aluminium' => ['DMP Aluminium', [192, 196, 200]],
        'handle' => ['DMP Handle', [58, 58, 60]]
      }.freeze

      module_function

      def drawer_set?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(DICT, 'type') == 'set'
      end

      # entities: where the set is created; transformation places the space origin.
      def create(entities, transformation, space, params)
        drawers = Calculator.compute(space, params)
        operation('Insert Drawers') do
          set = entities.add_group
          set.transformation = transformation
          fill(set, space, params, drawers)
          set
        end
      end

      def rebuild(set, params)
        space = JSON.parse(set.get_attribute(DICT, 'space'))
        drawers = Calculator.compute(space, params)
        operation('Edit Drawers') do
          clear(set)
          fill(set, space, params, drawers)
          set
        end
      end

      def operation(name)
        model = Sketchup.active_model
        model.start_operation(name, true)
        begin
          result = yield
          model.commit_operation
          result
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      # Empties a set and removes the door/drawer definitions it owned.
      def clear(set)
        set.make_unique
        owned = []
        collect_owned(set.entities, owned)
        set.entities.clear!
        definitions = Sketchup.active_model.definitions
        owned.uniq.each do |definition|
          next unless definition.valid? && definition.instances.empty?

          definitions.remove(definition) if definitions.respond_to?(:remove)
        end
      end

      def collect_owned(entities, owned)
        entities.grep(Sketchup::ComponentInstance).each do |instance|
          definition = instance.definition
          next unless definition.get_attribute(DICT, 'owned')

          owned << definition
          collect_owned(definition.entities, owned)
        end
      end

      def fill(set, space, params, drawers)
        p = Calculator.normalize(params)
        set.name = "#{p['name']} set (#{drawers.size})"
        set.set_attribute(DICT, 'type', 'set')
        set.set_attribute(DICT, 'space', JSON.generate(space))
        set.set_attribute(DICT, 'params', JSON.generate(p))
        cache = hardware_cache
        fixed = drawers.flat_map { |drawer| drawer[:fixed] || [] }
        add_static(set.entities, "#{p['name']} rel & profil", 'fixed', fixed, p['name'], cache)
        drawers.each do |drawer|
          add_mover(set.entities, "#{p['name']} #{drawer[:index]}", drawer[:parts], p['name'], cache,
                    kind: 'drawer', origin: [0.0, 0.0, 0.0], travel: drawer[:travel])
        end
      end

      def add_static(entities, name, type, parts, set_name, cache)
        return nil if parts.empty?

        group = entities.add_group
        group.name = name
        group.set_attribute(DICT, 'type', type)
        parts.each { |part| add_part(group.entities, part, set_name, cache) }
        group
      end

      # Wrapper DC placed at the pivot (door) or origin (drawer); the moving child
      # starts at identity so ANIMATE runs from 0 = closed.
      def add_mover(entities, name, parts, set_name, cache, kind:, origin:, travel: 0.0, side: 'left', angle: 100.0)
        definitions = Sketchup.active_model.definitions
        wrapper = definitions.add(name)
        mover = definitions.add("#{name} (gerak)")
        [wrapper, mover].each { |definition| definition.set_attribute(DICT, 'owned', true) }
        ox, oy, oz = origin
        parts.each { |part| add_part(mover.entities, part, set_name, cache, [ox, oy, oz]) }
        child = wrapper.entities.add_instance(mover, Geom::Transformation.new)
        child.name = "#{name} (gerak)"
        child.set_attribute(DICT, 'type', 'mover')
        instance = entities.add_instance(wrapper, Geom::Transformation.translation([ox.mm, oy.mm, oz.mm]))
        instance.name = name
        instance.set_attribute(DICT, 'type', kind)
        if kind == 'door'
          signed = side == 'left' ? -angle : angle
          formula = format('ANIMATE("rotz",0,%g)', signed.round(1))
          instance.set_attribute(DICT, 'side', side)
          instance.set_attribute(DICT, 'angle', angle)
        else
          formula = format('ANIMATE("y",0,%g)', (-travel / 10.0).round(2))
          instance.set_attribute(DICT, 'travel', travel)
        end
        dynamic(wrapper, name)
        dynamic(mover, name, onclick: formula)
        instance
      end

      def dynamic(definition, name, onclick: nil)
        definition.set_attribute(DC, '_formatversion', 1.0)
        definition.set_attribute(DC, '_lengthunits', 'CENTIMETERS')
        definition.set_attribute(DC, '_name', name)
        definition.set_attribute(DC, 'name', name)
        return unless onclick

        definition.set_attribute(DC, 'onclick', onclick)
        definition.set_attribute(DC, '_onclick_label', 'onClick')
        definition.set_attribute(DC, '_hasbehaviors', 1.0)
      end

      def hardware_cache
        Sketchup.active_model.definitions.each_with_object({}) do |definition, cache|
          key = definition.get_attribute(DICT, 'hw_key')
          cache[key] = definition if key
        end
      end

      def add_part(entities, part, set_name, cache = {}, offset = [0.0, 0.0, 0.0])
        ox, oy, oz = offset
        entity = if part.hardware?
                   definition = hardware_definition(part, cache)
                   entities.add_instance(definition, Geom::Transformation.translation(
                                                       [(part.x - ox).mm, (part.y - oy).mm, (part.z - oz).mm]
                                                     ))
                 else
                   group = entities.add_group
                   geometry(group.entities, part, part.x - ox, part.y - oy, part.z - oz)
                   group
                 end
        entity.name = part.name
        entity.material = material_for(part)
        tag(entity, part, set_name)
        entity
      end

      def tag(entity, part, set_name)
        info = part.info || {}
        entity.set_attribute(DICT, 'type', 'part')
        entity.set_attribute(DICT, 'set', set_name)
        entity.set_attribute(DICT, 'role', part.role)
        entity.set_attribute(DICT, 'kind', part.kind)
        if part.hardware?
          entity.set_attribute(DICT, 'desc', info[:desc].to_s)
          entity.set_attribute(DICT, 'qty', info[:qty].to_f)
          entity.set_attribute(DICT, 'length', info[:length].to_f.round(1)) if info[:length]
        else
          entity.set_attribute(DICT, 'material_key', info[:material].to_s)
          %i[finish_l finish_w thickness cut_l cut_w].each do |key|
            entity.set_attribute(DICT, key.to_s, info[key].to_f.round(1))
          end
          entity.set_attribute(DICT, 'band', JSON.generate(info[:band] || {}))
          entity.set_attribute(DICT, 'grain', info[:len_axis].to_s)
        end
      end

      def hardware_definition(part, cache)
        dims = [part.dx, part.dy, part.dz].map { |value| value.round(2) }
        key = [part.role, part.shape, part.axis, dims, (part.profile || []).flatten.map { |v| v.round(2) }].inspect
        cached = cache[key]
        return cached if cached&.valid?

        definition = Sketchup.active_model.definitions.add("DMP #{part.info[:desc]}")
        definition.set_attribute(DICT, 'hw_key', key)
        geometry(definition.entities, part, 0.0, 0.0, 0.0)
        cache[key] = definition
      end

      def geometry(entities, part, x, y, z)
        case part.shape
        when 'profile' then profile(entities, part, x, y, z)
        when 'cylinder' then cylinder(entities, part, x, y, z)
        else box(entities, x, y, z, part.dx, part.dy, part.dz)
        end
      end

      def point(x, y, z)
        Geom::Point3d.new(x.mm, y.mm, z.mm)
      end

      def box(entities, x, y, z, dx, dy, dz)
        face = entities.add_face([point(x, y, z), point(x + dx, y, z), point(x + dx, y + dy, z), point(x, y + dy, z)])
        face.reverse! if face.normal.z.negative?
        face.pushpull(dz.mm)
      end

      def axis_data(part)
        case part.axis
        when 'x' then [Geom::Vector3d.new(1, 0, 0), part.dx]
        when 'y' then [Geom::Vector3d.new(0, 1, 0), part.dy]
        else [Geom::Vector3d.new(0, 0, 1), part.dz]
        end
      end

      def profile(entities, part, x, y, z)
        points = part.profile.map do |u, v|
          case part.axis
          when 'x' then point(x, y + u, z + v)
          when 'y' then point(x + u, y, z + v)
          else point(x + u, y + v, z)
          end
        end
        normal, length = axis_data(part)
        face = entities.add_face(points)
        face.reverse! if face.normal % normal < 0
        face.pushpull(length.mm)
      end

      def cylinder(entities, part, x, y, z)
        normal, length = axis_data(part)
        case part.axis
        when 'x' then centre = point(x, y + part.dy / 2.0, z + part.dz / 2.0); radius = [part.dy, part.dz].min / 2.0
        when 'y' then centre = point(x + part.dx / 2.0, y, z + part.dz / 2.0); radius = [part.dx, part.dz].min / 2.0
        else centre = point(x + part.dx / 2.0, y + part.dy / 2.0, z); radius = [part.dx, part.dy].min / 2.0
        end
        edges = entities.add_circle(centre, normal, radius.mm, radius < 6 ? 12 : 24)
        face = entities.add_face(edges)
        face.reverse! if face.normal % normal < 0
        face.pushpull(length.mm)
      end

      def material_for(part)
        key = if %w[handle knob].include?(part.role) && part.info[:material] != 'aluminium'
                'handle'
              else
                part.info[:material] || 'metal'
              end
        name, rgb, alpha = MATERIALS.fetch(key, MATERIALS['carcass'])
        materials = Sketchup.active_model.materials
        materials[name] || materials.add(name).tap do |material|
          material.color = Sketchup::Color.new(*rgb)
          material.alpha = alpha if alpha
        end
      end
    end
  end
end
