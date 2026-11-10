require 'minitest/autorun'
require_relative '../src/drawer_maker_pro/calculator'
require_relative '../src/drawer_maker_pro/cutlist'

class CalculatorTest < Minitest::Test
  C = SketchupCloud::DrawerMakerPro::Calculator
  SPACE = { 'width' => 600.0, 'depth' => 550.0, 'height' => 720.0 }.freeze

  def test_split_equal
    assert_equal [240.0, 240.0, 240.0], C.split_lengths('3', 720)
  end

  def test_split_ratio
    assert_equal [180.0, 180.0, 360.0], C.split_lengths('1:1:2', 720)
  end

  def test_split_fixed_plus_ratio
    assert_equal [200.0, 260.0, 260.0], C.split_lengths('200:1:1', 720)
  end

  def test_split_errors
    assert_raises(ArgumentError) { C.split_lengths('', 720) }
    assert_raises(ArgumentError) { C.split_lengths('500:400', 720) }
    assert_raises(ArgumentError) { C.split_lengths('a:1', 720) }
    assert_raises(ArgumentError) { C.split_lengths('0', 720) }
  end

  def test_vertical_stack_top_down_spec
    d = C.compute(SPACE, 'quantity' => '200:1:1', 'handle' => 'none')
    assert_equal 3, d.size
    # spec is top-down, cells are built bottom-up
    assert_in_delta 0.0, d[0][:cell]['z']
    assert_in_delta 260.0, d[0][:cell]['height']
    assert_in_delta 520.0, d[2][:cell]['z']
    assert_in_delta 200.0, d[2][:cell]['height']
  end

  def test_inset_part_sizes
    p = { 'quantity' => '1', 'handle' => 'none', 'gap' => 3, 'front_thickness' => 18,
          'board_thickness' => 15, 'slide_clearance' => 12.5, 'drawer_depth' => 450,
          'top_clearance' => 25, 'bottom_clearance' => 15, 'bottom_raise' => 12, 'bottom_thickness' => 9 }
    parts = C.compute(SPACE, p)[0][:parts].each_with_object({}) { |x, h| h[x.role] ||= x }
    f = parts['front']
    assert_equal [1.5, 0.0, 1.5, 597.0, 18.0, 717.0], [f.x, f.y, f.z, f.dx, f.dy, f.dz]
    side = parts['side']
    assert_equal [12.5, 18.0, 15.0, 15.0, 450.0, 680.0], [side.x, side.y, side.z, side.dx, side.dy, side.dz]
    assert_equal 545.0, parts['sub_front'].dx # 600 - 2*12.5 - 2*15
    assert_equal({ length: 545.0, width: 435.0, thickness: 9.0 }, parts['bottom'].cut_size)
    assert_in_delta 680 - 12 - 9, parts['back'].dz
    parts.each_value { |x| assert x.y + x.dy <= SPACE['depth'] + 1e-6, x.name }
  end

  def test_auto_depth_and_overlay
    p = { 'quantity' => '2', 'front_mode' => 'overlay', 'overlay' => 10, 'gap' => 2, 'handle' => 'bar' }
    parts = C.compute(SPACE, p)[0][:parts]
    front = parts.find { |x| x.role == 'front' }
    assert_equal(-18.0, front.y)
    assert_in_delta 600 + 20 - 2, front.dx
    side = parts.find { |x| x.role == 'side' }
    assert_in_delta 550 - 10, side.dy # auto depth = space depth - back clearance
    handle = parts.find { |x| x.role == 'handle' }
    assert handle.y + handle.dy <= front.y + 1e-6
  end

  def test_horizontal_and_gola
    d = C.compute(SPACE, 'quantity' => '2', 'layout' => 'horizontal', 'handle' => 'gola', 'gola_gap' => 30, 'gap' => 3)
    assert_in_delta 300.0, d[1][:cell]['x']
    front = d[0][:parts].find { |x| x.role == 'front' }
    assert_in_delta 720 - 3 - 30, front.dz
    refute(d[0][:parts].any? { |x| x.role == 'handle' })
  end

  def test_too_small
    assert_raises(ArgumentError) { C.compute(SPACE, 'quantity' => '15') }
  end

  def test_cutlist_aggregate
    rows = [
      { set: 'D', role: 'side', length: 450, width: 150, thickness: 15, material: 'Box' },
      { set: 'D', role: 'side', length: 450, width: 150, thickness: 15, material: 'Box' },
      { set: 'D', role: 'front', length: 597, width: 200, thickness: 18, material: 'Front' }
    ]
    agg = SketchupCloud::DrawerMakerPro::CutList.aggregate(rows)
    assert_includes agg, ['D', 'side', 450.0, 150.0, 15.0, 2, 'Box']
    assert_equal 2, agg.size
  end
end
