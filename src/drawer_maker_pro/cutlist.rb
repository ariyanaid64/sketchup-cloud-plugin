require 'csv'
require 'json'

module SketchupCloud
  module DrawerMakerPro
    # Workshop export: panel cut list (finished and cut sizes after edge
    # banding), hardware BOM and edge-banding totals in one CSV file.
    module CutList
      PANEL_HEADER = ['Set', 'Part', 'Material', 'Finish L (mm)', 'Finish W (mm)', 'Tebal (mm)',
                      'Cut L (mm)', 'Cut W (mm)', 'EB L1', 'EB L2', 'EB W1', 'EB W2', 'Serat', 'Qty'].freeze
      HARDWARE_HEADER = ['Set', 'Item', 'Qty', 'Total panjang (mm)'].freeze

      module_function

      def panel_rows(rows)
        counts = Hash.new(0)
        rows.select { |r| r[:kind] != 'hardware' }.each do |r|
          band = r[:band] || {}
          key = [r[:set].to_s, r[:role].to_s, r[:material].to_s,
                 r[:finish_l].to_f.round(1), r[:finish_w].to_f.round(1), r[:thickness].to_f.round(1),
                 r[:cut_l].to_f.round(1), r[:cut_w].to_f.round(1),
                 *%w[l1 l2 w1 w2].map { |edge| band[edge].to_f.round(1) }, grain_label(r[:grain])]
          counts[key] += 1
        end
        counts.map { |key, qty| key + [qty] }.sort_by { |r| [r[0], r[1], -r[3]] }
      end

      def grain_label(axis)
        axis.to_s.empty? ? '' : "sepanjang L (#{axis.upcase})"
      end

      def hardware_rows(rows)
        totals = Hash.new { |hash, key| hash[key] = [0.0, 0.0] }
        rows.select { |r| r[:kind] == 'hardware' }.each do |r|
          entry = totals[[r[:set].to_s, r[:desc].to_s]]
          entry[0] += r[:qty].to_f
          entry[1] += r[:length].to_f if r[:qty].to_f.positive?
        end
        totals.reject { |_, (qty, _)| qty.zero? }
              .map { |(set, desc), (qty, length)| [set, desc, format_qty(qty), length.positive? ? length.round : ''] }
              .sort
      end

      def format_qty(qty)
        (qty % 1).zero? ? qty.to_i : qty.round(2)
      end

      # Banding metres per thickness, from finished edge lengths.
      def banding_rows(rows)
        totals = Hash.new(0.0)
        rows.select { |r| r[:kind] != 'hardware' }.each do |r|
          band = r[:band] || {}
          { 'l1' => r[:finish_l], 'l2' => r[:finish_l], 'w1' => r[:finish_w], 'w2' => r[:finish_w] }.each do |edge, length|
            thickness = band[edge].to_f
            totals[thickness.round(1)] += length.to_f if thickness.positive?
          end
        end
        totals.sort.map { |thickness, length| ["Edge banding #{thickness} mm", (length / 1000.0).round(2)] }
      end

      def to_csv(rows)
        CSV.generate do |csv|
          csv << ['CUT LIST PANEL']
          csv << PANEL_HEADER
          panel_rows(rows).each { |row| csv << row }
          csv << []
          csv << ['HARDWARE']
          csv << HARDWARE_HEADER
          hardware_rows(rows).each { |row| csv << row }
          csv << []
          csv << ['EDGE BANDING', 'Total (m)']
          banding_rows(rows).each { |row| csv << row }
        end
      end

      def collect(entities, rows = [])
        entities.each do |e|
          next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

          if e.get_attribute(Builder::DICT, 'type') == 'part'
            rows << row_for(e)
          else
            collect(e.definition.entities, rows)
          end
        end
        rows
      end

      def row_for(entity)
        read = ->(key) { entity.get_attribute(Builder::DICT, key) }
        kind = read.call('kind') || 'panel'
        row = { set: read.call('set'), role: read.call('role'), kind: kind }
        if kind == 'hardware'
          row.merge(desc: read.call('desc'), qty: read.call('qty') || 1, length: read.call('length'))
        else
          band = begin
            JSON.parse(read.call('band') || '{}')
          rescue JSON::ParserError
            {}
          end
          # Parts from version 1.x only stored length/width/thickness.
          row.merge(material: entity.material ? entity.material.display_name : '',
                    finish_l: read.call('finish_l') || read.call('length'),
                    finish_w: read.call('finish_w') || read.call('width'),
                    thickness: read.call('thickness'),
                    cut_l: read.call('cut_l') || read.call('length'),
                    cut_w: read.call('cut_w') || read.call('width'),
                    band: band, grain: read.call('grain'))
        end
      end

      def export
        model = Sketchup.active_model
        rows = collect(model.entities)
        if rows.empty?
          UI.messagebox('Tidak ada part Drawer Maker Pro di model ini.')
          return
        end
        path = UI.savepanel('Export Cut List', '', 'cutlist_produksi.csv')
        return unless path

        path += '.csv' unless path.downcase.end_with?('.csv')
        File.write(path, to_csv(rows))
        UI.messagebox("Cut list diekspor (#{rows.size} item):\n#{path}")
      end
    end
  end
end
