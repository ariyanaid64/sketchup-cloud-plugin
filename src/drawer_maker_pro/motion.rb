module SketchupCloud
  module DrawerMakerPro
    # Doors and drawers open through the Dynamic Components Interact tool.
    # This only returns everything in a set to the closed position.
    module Motion
      module_function

      def close_all(set)
        raise ArgumentError, 'Set terkunci.' if set.locked?

        Builder.operation('Tutup semua pintu & laci') do
          set.make_unique
          movers = set.entities.select do |entity|
            (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) &&
              %w[drawer door].include?(entity.get_attribute(Builder::DICT, 'type'))
          end
          raise ArgumentError, 'Set ini tidak memiliki pintu atau laci.' if movers.empty?

          movers.each { |entity| close(entity) }
          movers.length
        end
      end

      def close(entity)
        if entity.is_a?(Sketchup::Group)
          # Sets made by version 1.1 moved the group itself.
          stored = entity.get_attribute(Builder::DICT, 'closed_transform')
          entity.transformation = Geom::Transformation.new(stored) if stored
          return
        end
        entity.definition.entities.grep(Sketchup::ComponentInstance).each do |child|
          next unless child.get_attribute(Builder::DICT, 'type') == 'mover'

          child.transformation = Geom::Transformation.new
          %w[rotz y].each do |key|
            child.set_attribute(Builder::DC, key, 0.0) if child.get_attribute(Builder::DC, key)
          end
        end
      end
    end
  end
end
