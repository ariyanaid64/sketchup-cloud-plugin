require 'csv'

module SketchupCloud
  module DrawerMakerPro
    module CutList
      HEADER = ['Set', 'Part', 'Length (mm)', 'Width (mm)', 'Thickness (mm)', 'Qty', 'Material'].freeze

      module_function

      # rows: hashes with :set, :role, :length, :width, :thickness, :material.
      # Identical parts are merged into one line with a quantity.
      def aggregate(rows)
        counts = Hash.new(0)
        rows.each do |r|
          key = [r[:set], r[:role], r[:length].to_f.round(1), r[:width].to_f.round(1),
                 r[:thickness].to_f.round(1), r[:material].to_s]
          counts[key] += 1
        end
        counts.map { |k, qty| k[0, 5] + [qty, k[5]] }.sort_by { |r| [r[0].to_s, r[1].to_s, -r[2]] }
      end

      def to_csv(rows)
        CSV.generate do |csv|
          csv << HEADER
          aggregate(rows).each { |r| csv << r }
        end
      end

      def collect(entities, rows = [])
        entities.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          if e.get_attribute(Builder::DICT, 'type') == 'part'
            rows << {
              set: e.get_attribute(Builder::DICT, 'set'),
              role: e.get_attribute(Builder::DICT, 'role'),
              length: e.get_attribute(Builder::DICT, 'length'),
              width: e.get_attribute(Builder::DICT, 'width'),
              thickness: e.get_attribute(Builder::DICT, 'thickness'),
              material: e.material ? e.material.display_name : ''
            }
          else
            collect(e.definition.entities, rows)
          end
        end
        rows
      end

      def export
        model = Sketchup.active_model
        rows = collect(model.entities)
        if rows.empty?
          UI.messagebox('No Drawer Maker Pro parts found in this model.')
          return
        end
        path = UI.savepanel('Export Cut List', '', 'drawer_cutlist.csv')
        return unless path

        path += '.csv' unless path.downcase.end_with?('.csv')
        File.write(path, to_csv(rows))
        UI.messagebox("Cut list exported (#{rows.size} parts):\n#{path}")
      end
    end
  end
end
