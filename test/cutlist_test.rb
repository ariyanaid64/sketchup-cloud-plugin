require_relative 'support/sketchup_fakes'
require 'csv'

class CutListTest < Minitest::Test
  include TestHelpers
  CutList = DMP::CutList
  DICT = DMP::Builder::DICT

  def panel(overrides = {})
    { set: 'S', role: 'front', kind: 'panel', material: 'DMP Front', finish_l: 597.0, finish_w: 237.0, thickness: 18.0,
      cut_l: 595.0, cut_w: 235.0, band: { 'l1' => 1.0, 'l2' => 1.0, 'w1' => 1.0, 'w2' => 1.0 }, grain: 'x' }.merge(overrides)
  end

  def hardware(overrides = {})
    { set: 'S', role: 'slide', kind: 'hardware', desc: 'Rel 500', qty: 0.5, length: 500.0 }.merge(overrides)
  end

  def test_panel_rows_group_identical_parts_and_show_cut_sizes
    rows = CutList.panel_rows([panel, panel, panel('role' => 'x', thickness: 15.0, finish_l: 500.0, cut_l: 500.0, band: {}), hardware])
    assert_equal 2, rows.size
    front = rows.find { |r| r[1] == 'front' && r[5] == 18.0 }
    assert_equal ['S', 'front', 'DMP Front', 597.0, 237.0, 18.0, 595.0, 235.0, 1.0, 1.0, 1.0, 1.0, 'sepanjang L (X)', 2], front
    assert_equal CutList::PANEL_HEADER.size, front.size
  end

  def test_panel_rows_are_sorted_by_set_part_and_descending_length
    rows = CutList.panel_rows([panel(role: 'side', finish_l: 100.0), panel(role: 'side', finish_l: 200.0), panel(set: 'A')])
    assert_equal %w[A S S], rows.map(&:first)
    assert_equal [200.0, 100.0], rows.select { |r| r[1] == 'side' }.map { |r| r[3] }
  end

  def test_hardware_rows_sum_quantity_and_length
    rows = CutList.hardware_rows([hardware, hardware, hardware(qty: 0, length: 500.0), hardware(desc: 'Pen', qty: 4, length: nil),
                                  hardware(desc: 'Nol', qty: 0), panel])
    # qty 0 rows (arms, drawer-side slide members) add nothing; length only counts for qty > 0.
    assert_equal [['S', 'Pen', 4, ''], ['S', 'Rel 500', 1, 1000]], rows
  end

  def test_fractional_quantities_are_kept
    rows = CutList.hardware_rows([hardware(qty: 0.5, length: nil)])
    assert_equal [['S', 'Rel 500', 0.5, '']], rows
  end

  def test_banding_rows_total_metres_per_thickness
    rows = [panel, panel, panel(band: { 'l1' => 0.4 }, finish_l: 500.0, finish_w: 100.0), hardware]
    # 1.0 mm: 2 x (2 x 597 + 2 x 237) = 3336 mm; 0.4 mm: one 500 mm edge.
    assert_equal [['Edge banding 0.4 mm', 0.5], ['Edge banding 1.0 mm', 3.34]], CutList.banding_rows(rows)
    assert_empty CutList.banding_rows([hardware])
  end

  def test_to_csv_has_the_three_sections
    csv = CSV.parse(CutList.to_csv([panel, panel, hardware, hardware]))
    assert_equal ['CUT LIST PANEL'], csv[0]
    assert_equal CutList::PANEL_HEADER, csv[1]
    assert_equal %w[S front], csv[2].first(2)
    assert_equal '2', csv[2].last
    hw = csv.index(['HARDWARE'])
    assert_equal CutList::HARDWARE_HEADER, csv[hw + 1]
    assert_equal ['S', 'Rel 500', '1', '1000'], csv[hw + 2]
    eb = csv.index(['EDGE BANDING', 'Total (m)'])
    assert_equal ['Edge banding 1.0 mm', '3.34'], csv[eb + 1]
  end

  def test_collect_reads_parts_from_a_built_set
    model = FakeSketchup::Model.new
    Sketchup.active_model = model
    DMP::Builder.create(model.entities, Geom::Transformation.new, { 'width' => 600, 'depth' => 550, 'height' => 720 }, 'quantity' => '1')
    rows = CutList.collect(model.entities)
    front = rows.find { |r| r[:role] == 'front' }
    assert_equal 'Drawer', front[:set]
    assert_equal 'DMP Front', front[:material]
    assert_equal [597.0, 717.0, 595.0, 715.0], front.values_at(:finish_l, :finish_w, :cut_l, :cut_w)
    assert_equal 1.0, front[:band]['l1']
    assert_equal 'x', front[:grain]
    slides = rows.select { |r| r[:role] == 'slide' }
    assert_equal 4, slides.size
    assert_equal [0, 0, 0.5, 0.5], slides.map { |r| r[:qty] }.sort
    # Panels and hardware both reach the export.
    assert_equal 6, rows.count { |r| r[:kind] == 'panel' && r[:role] != 'handle' }
    csv = CutList.to_csv(rows)
    assert_includes csv, 'Rel ball bearing full extension NL 500 mm (pasang),1,""'
  end

  def test_legacy_v1_parts_fall_back_to_length_and_width
    entity = FakeSketchup::Group.new
    entity.set_attribute(DICT, 'type', 'part')
    entity.set_attribute(DICT, 'set', 'Old')
    entity.set_attribute(DICT, 'role', 'side')
    entity.set_attribute(DICT, 'length', 600.0)
    entity.set_attribute(DICT, 'width', 400.0)
    entity.set_attribute(DICT, 'thickness', 18.0)
    row = CutList.row_for(entity)
    assert_equal 'panel', row[:kind]
    assert_equal [600.0, 400.0, 600.0, 400.0], row.values_at(:finish_l, :finish_w, :cut_l, :cut_w)
    assert_equal({}, row[:band])
    assert_equal '', row[:material]
    assert_nil row[:grain]
    assert_equal ['Old', 'side', '', 600.0, 400.0, 18.0, 600.0, 400.0, 0.0, 0.0, 0.0, 0.0, '', 1],
                 CutList.panel_rows([row]).first
    assert_empty CutList.banding_rows([row])
  end

  def test_corrupt_band_json_is_ignored
    entity = FakeSketchup::Group.new
    entity.set_attribute(DICT, 'type', 'part')
    entity.set_attribute(DICT, 'band', '{nope')
    assert_equal({}, CutList.row_for(entity)[:band])
  end

  def test_legacy_hardware_rows_default_to_quantity_one
    entity = FakeSketchup::Group.new
    entity.set_attribute(DICT, 'type', 'part')
    entity.set_attribute(DICT, 'kind', 'hardware')
    entity.set_attribute(DICT, 'set', 'Old')
    entity.set_attribute(DICT, 'desc', 'Knob')
    row = CutList.row_for(entity)
    assert_equal 1, row[:qty]
    assert_equal [['Old', 'Knob', 1, '']], CutList.hardware_rows([row])
  end
end
