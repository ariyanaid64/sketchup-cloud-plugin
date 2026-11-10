module SketchupCloud
  module DrawerMakerPro
    module Motion
      module_function

      def toggle(set)
        raise ArgumentError, 'Set terkunci.' if set.locked?
        model = Sketchup.active_model
        model.start_operation('Open / Close', true)
        begin
          set.make_unique
          moving = set.entities.grep(Sketchup::Group).select do |group|
            %w[drawer door].include?(group.get_attribute(Builder::DICT, 'type'))
          end
          raise ArgumentError, 'Set ini tidak memiliki pintu atau laci.' if moving.empty?

          opening = !set.get_attribute(Builder::DICT, 'open', false)
          moving.each do |group|
            stored = group.get_attribute(Builder::DICT, 'closed_transform')
            closed = stored ? Geom::Transformation.new(stored) : group.transformation
            group.set_attribute(Builder::DICT, 'closed_transform', closed.to_a)
            group.transformation = opening ? movement(group) * closed : closed
          end
          set.set_attribute(Builder::DICT, 'open', opening)
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def movement(group)
        if group.get_attribute(Builder::DICT, 'type') == 'drawer'
          distance = group.get_attribute(Builder::DICT, 'travel', 300.0).to_f
          Geom::Transformation.translation([0, -distance.mm, 0])
        else
          x = group.get_attribute(Builder::DICT, 'hinge_x').to_f.mm
          y = group.get_attribute(Builder::DICT, 'hinge_y', 0).to_f.mm
          angle = group.get_attribute(Builder::DICT, 'side') == 'left' ? -90 : 90
          Geom::Transformation.rotation([x, y, 0], [0, 0, 1], angle.degrees)
        end
      end
    end
  end
end
