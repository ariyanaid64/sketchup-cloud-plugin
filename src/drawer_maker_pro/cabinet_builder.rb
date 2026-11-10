require 'json'
require_relative 'cabinet_calculator'

module SketchupCloud
  module DrawerMakerPro
    # Builds and edits cabinet sets in SketchUp using the shared part builder.
    module CabinetBuilder
      DICT = Builder::DICT

      module_function

      def cabinet_set?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(DICT, 'type') == 'cabinet_set'
      end

      # `transformation` places the space's front-bottom-left origin.
      def create(entities, transformation, space, params = {})
        layout = CabinetCalculator.compute(space, params)
        model = Sketchup.active_model
        model.start_operation('Insert Cabinet', true)
        begin
          set = entities.add_group
          set.transformation = transformation
          fill(set, space, params, layout)
          model.commit_operation
          set
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def rebuild(set, params)
        raise ArgumentError, 'Entity is not a cabinet set' unless cabinet_set?(set)

        space = JSON.parse(set.get_attribute(DICT, 'space'))
        layout = CabinetCalculator.compute(space, params)
        model = Sketchup.active_model
        model.start_operation('Edit Cabinet', true)
        begin
          set.make_unique
          set.entities.clear!
          fill(set, space, params, layout)
          model.commit_operation
          set
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def fill(set, space, params, layout)
        p = CabinetCalculator.normalize(params)
        set.name = "#{p['name']} set"
        set.set_attribute(DICT, 'type', 'cabinet_set')
        set.set_attribute(DICT, 'space', JSON.generate(space))
        set.set_attribute(DICT, 'params', JSON.generate(p))
        set.set_attribute(DICT, 'openings', JSON.generate(layout[:openings]))
        set.set_attribute(DICT, 'open', false)

        carcass = set.entities.add_group
        carcass.name = "#{p['name']} Carcass"
        carcass.set_attribute(DICT, 'type', 'carcass')
        layout[:parts].each { |part| Builder.add_part(carcass.entities, part, p['name']) }

        layout[:doors].each do |door|
          group = set.entities.add_group
          group.name = door[:name]
          group.set_attribute(DICT, 'type', 'door')
          group.set_attribute(DICT, 'hinge_x', door[:hinge_x])
          group.set_attribute(DICT, 'hinge_z', door[:hinge_z])
          group.set_attribute(DICT, 'side', door[:side])
          door[:parts].each { |part| Builder.add_part(group.entities, part, p['name']) }
        end
        set
      end
    end
  end
end
