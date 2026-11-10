require 'json'
require_relative 'cabinet_calculator'

module SketchupCloud
  module DrawerMakerPro
    # Builds and edits cabinet sets: static carcass + hardware, doors and
    # drawers as Dynamic Components (see Builder.add_mover).
    module CabinetBuilder
      DICT = Builder::DICT

      module_function

      def cabinet_set?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(DICT, 'type') == 'cabinet_set'
      end

      # `transformation` places the cabinet's external front-bottom-left corner.
      def create(entities, transformation, space, params = {})
        layout = CabinetCalculator.compute(space, params)
        Builder.operation('Insert Cabinet') do
          set = entities.add_group
          set.transformation = transformation
          fill(set, space, params, layout)
          set
        end
      end

      def rebuild(set, params)
        raise ArgumentError, 'Objek terpilih bukan set kabinet' unless cabinet_set?(set)

        space = JSON.parse(set.get_attribute(DICT, 'space'))
        layout = CabinetCalculator.compute(space, params)
        Builder.operation('Edit Cabinet') do
          Builder.clear(set)
          fill(set, space, params, layout)
          set
        end
      end

      def fill(set, space, params, layout)
        p = CabinetCalculator.normalize(params)
        set.name = "#{p['name']} set"
        set.set_attribute(DICT, 'type', 'cabinet_set')
        set.set_attribute(DICT, 'space', JSON.generate(space))
        set.set_attribute(DICT, 'params', JSON.generate(p))
        set.set_attribute(DICT, 'openings', JSON.generate(layout[:openings]))
        cache = Builder.hardware_cache
        carcass = Builder.add_static(set.entities, "#{p['name']} Carcass", 'carcass', layout[:parts], p['name'], cache)
        carcass&.set_attribute(DICT, 'type', 'carcass')
        layout[:doors].each do |door|
          Builder.add_mover(set.entities, door[:name], door[:parts], p['name'], cache,
                            kind: 'door', origin: [door[:hinge_x], door[:hinge_y], 0.0],
                            side: door[:side], angle: door[:angle])
        end
        layout[:drawers].each do |drawer|
          Builder.add_mover(set.entities, drawer[:name], drawer[:parts], p['name'], cache,
                            kind: 'drawer', origin: [0.0, 0.0, 0.0], travel: drawer[:travel])
        end
        set
      end
    end
  end
end
