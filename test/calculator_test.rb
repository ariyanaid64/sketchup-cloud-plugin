require_relative 'support/sketchup_fakes'

# Standalone drawer sets: fronts, boxes, slides and travel (millimetres).
class CalculatorTest < Minitest::Test
  include TestHelpers
  Calc = DMP::Calculator
  SPACE = { 'width' => 600, 'depth' => 550, 'height' => 720 }.freeze

  def drawers(params = {}, space = SPACE) = Calc.compute(space, params)
  def one(params = {}, space = SPACE) = drawers({ 'quantity' => '1' }.merge(params), space).first
  def moving(drawer, name) = part(drawer[:parts], "Drawer 1 - #{name}")
  def fixed(drawer, name) = part(drawer[:fixed], "Drawer 1 - #{name}")

  def test_default_set_has_three_stacked_cells_and_unit_structure
    result = drawers
    assert_equal [1, 2, 3], result.map { |d| d[:index] }
    assert_equal [240.0] * 3, result.map { |d| d[:cell]['height'] }
    assert_equal [0.0, 240.0, 480.0], result.map { |d| d[:cell]['z'] }
    assert_equal %w[front side side sub_front back bottom slide slide],
                 result[0][:parts].map(&:role) - %w[handle]
    assert_equal %w[slide slide], result[0][:fixed].map(&:role)
  end

  def test_default_front_cut_size_edge_banding_and_box_geometry
    d = drawers.first
    front = moving(d, 'Front')
    assert_equal [1.5, 0.0, 1.5, 597.0, 18.0, 237.0], box_of(front)
    assert_equal 'x', front.info[:len_axis]
    assert_equal({ l1: 1.0, l2: 1.0, w1: 1.0, w2: 1.0 }, front.info[:band])
    assert_equal 595.0, front.info[:cut_l]
    assert_equal 235.0, front.info[:cut_w]

    side = moving(d, 'Side L')
    assert_equal [12.7, 18.0, 15.0, 15.0, 500.0, 200.0], box_of(side)
    assert_equal [572.3, 18.0, 15.0, 15.0, 500.0, 200.0], box_of(moving(d, 'Side R'))
    assert_equal 0.4, side.info[:band][:l1]

    assert_equal [22.7, 28.0, 27.0, 554.6, 480.0, 6.0], box_of(moving(d, 'Bottom'))
    assert_equal 450.0, d[:travel]
  end

  def test_ball_bearing_members_both_sides
    d = one
    # Cabinet member on the opening wall, drawer member against the box; 12.7 mm / 2 each.
    assert_equal [0.0, 18.0, 25.0, 6.35, 500.0, 45.0], box_of(fixed(d, 'Slide L (kabinet)'))
    assert_equal [6.35, 18.0, 25.0, 6.35, 500.0, 45.0], box_of(moving(d, 'Slide L (laci)'))
    assert_equal [593.65, 18.0, 25.0, 6.35, 500.0, 45.0], box_of(fixed(d, 'Slide R (kabinet)'))
    assert_equal [587.3, 18.0, 25.0, 6.35, 500.0, 45.0], box_of(moving(d, 'Slide R (laci)'))
    assert_equal [0.5, 0.5, 0, 0], [fixed(d, 'Slide L (kabinet)'), fixed(d, 'Slide R (kabinet)'),
                                    moving(d, 'Slide L (laci)'), moving(d, 'Slide R (laci)')].map { |s| s.info[:qty] }
    assert_in_delta moving(d, 'Side L').x, moving(d, 'Slide L (laci)').x + 6.35, 1e-9
  end

  def test_slide_members_follow_a_shifted_opening
    front = { x: 150.0, y: 0.0, z: 0.0, w: 400.0, h: 200.0, box_y: 18.0 }
    opening = { 'x' => 100.0, 'z' => 0.0, 'width' => 450.0, 'height' => 200.0, 'depth' => 550.0 }
    unit = Calc.drawer_unit('Drawer 1', front, opening, Calc.normalize({}))
    d = { parts: unit[:moving], fixed: unit[:fixed] }
    assert_equal 100.0, fixed(d, 'Slide L (kabinet)').x
    assert_close 106.35, moving(d, 'Slide L (laci)').x
    assert_close 543.65, fixed(d, 'Slide R (kabinet)').x
    assert_close 537.3, moving(d, 'Slide R (laci)').x
  end

  def test_roller_slides_use_clearance_25mm_height_and_three_quarter_travel
    d = one('slide_type' => 'roller')
    assert_equal 12.5, moving(d, 'Side L').x
    assert_equal [0.0, 18.0, 15.0, 6.25, 500.0, 25.0], box_of(fixed(d, 'Slide L (kabinet)'))
    assert_equal 375.0, d[:travel]
  end

  def test_undermount_runner_sits_inside_the_13mm_recess
    d = one('slide_type' => 'undermount')
    assert_equal 5.0, moving(d, 'Side L').x
    assert_equal 580.0, moving(d, 'Side R').x
    left = fixed(d, 'Slide L')
    right = fixed(d, 'Slide R')
    assert_equal 20.0, left.x # 5 clearance + 15 side
    assert_equal [25.0, 490.0], [left.dx, left.dy] # nominal 500 less 10 at the rear
    assert_equal 555.0, right.x
    assert_operator left.z + left.dz, :<=, moving(d, 'Bottom').z
    assert_equal 450.0, d[:travel]
    assert_equal 'Rel undermount soft-close full extension NL 500 mm (pasang)', left.info[:desc]
  end

  def test_custom_slide_uses_given_clearance
    d = one('slide_type' => 'custom', 'slide_clearance' => 10.0)
    assert_equal 10.0, moving(d, 'Side L').x
    assert_equal 'Rel laci (custom) NL 500 mm (pasang)', fixed(d, 'Slide L (kabinet)').info[:desc]
  end

  def test_slide_nominal_length_auto_and_requested
    shallow = { 'width' => 600, 'depth' => 400, 'height' => 300 }
    d = one({}, shallow)
    assert_equal 350.0, moving(d, 'Side L').dy
    assert_in_delta 315.0, d[:travel]
    d = one({ 'slide_length' => 300 }, shallow)
    assert_equal 300.0, moving(d, 'Side L').dy
    assert_in_delta 270.0, d[:travel]
    assert_raises(ArgumentError) { one({ 'slide_length' => 450 }, shallow) }
    assert_raises(ArgumentError) { one({}, { 'width' => 600, 'depth' => 250, 'height' => 300 }) }
  end

  def test_nailed_bottom_sits_under_the_box
    d = one('drawer_bottom' => 'nailed')
    bottom = moving(d, 'Bottom')
    assert_equal 6.0, bottom.dz
    assert_equal 500.0, bottom.dy
    assert_equal 18.0, bottom.y
    assert_equal moving(d, 'Side L').x, bottom.x
    assert_equal 12.7, moving(d, 'Side L').x
    assert_equal 574.6, bottom.dx
    assert_operator bottom.z + bottom.dz, :<=, moving(d, 'Side L').z + 1e-9
  end

  def test_groove_bottom_is_captured_by_the_sides
    d = one
    left = moving(d, 'Side L')
    right = moving(d, 'Side R')
    bottom = moving(d, 'Bottom')
    assert_equal 6.0, bottom.dz
    assert_close 5.0, left.x + left.dx - bottom.x # 6 mm groove less 1 mm
    assert_close 5.0, bottom.x + bottom.dx - right.x
    assert_equal 28.0, bottom.y # 18 front + 15 front board - 5 groove
    assert_equal 480.0, bottom.dy
  end

  def test_dado_joint_changes_the_box_construction
    butt = one
    dado = one('drawer_joint' => 'dado')
    refute_equal box_of(moving(butt, 'Sub Front')), box_of(moving(dado, 'Sub Front'))
    assert_operator moving(dado, 'Sub Front').dx, :>, moving(butt, 'Sub Front').dx
  end

  def test_metal_sides_are_thin
    d = one('drawer_type' => 'metal')
    assert_equal 13.0, moving(d, 'Side L').dx
    assert_equal 12.7, moving(d, 'Side L').x
    assert_equal 25.7, moving(d, 'Bottom').x # bottom is not grooved into metal sides
  end

  def test_rail_drawer_has_lower_sides_and_gallery_rails
    d = one('drawer_type' => 'rail')
    assert_equal 590.0, moving(d, 'Side L').dz
    assert_equal 680.0, moving(d, 'Back').dz
    rails = d[:parts].select { |pt| pt.role == 'rail' }
    assert_equal 2, rails.size
    assert(rails.all? { |r| r.shape == 'cylinder' && r.axis == 'y' && r.dy == 500.0 && r.dx == 10.0 })
    assert_close 15.2, rails[0].x
    assert_close 574.8, rails[1].x
  end

  def test_overlay_front_covers_the_opening_edges
    result = drawers('front_mode' => 'overlay', 'quantity' => '2')
    lower = part(result[0][:parts], 'Drawer 1 - Front')
    upper = part(result[1][:parts], 'Drawer 2 - Front')
    assert_equal [-14.5, -18.0, -14.5, 629.0, 18.0, 373.0], box_of(lower)
    assert_equal 361.5, upper.z
  end

  def test_split_ratios_and_fixed_heights
    heights = ->(q) { drawers('quantity' => q).map { |d| d[:cell]['height'] } }
    assert_equal [240.0] * 3, heights.call('3')
    # The spec is written top-down; cells are stacked bottom-up.
    assert_equal [180.0, 180.0, 360.0], heights.call('2:1:1')
    assert_equal [260.0, 260.0, 200.0], heights.call('200:1:1')
    assert_raises(ArgumentError) { heights.call('') }
    assert_raises(ArgumentError) { heights.call('a:b') }
  end

  def test_horizontal_layout_splits_the_width
    result = drawers('layout' => 'horizontal', 'quantity' => '2')
    assert_equal [0.0, 300.0], result.map { |d| d[:cell]['x'] }
    assert_equal [300.0, 300.0], result.map { |d| d[:cell]['width'] }
    assert_equal [true, false], result.map { |d| d[:cell]['left_edge'] }
  end

  def test_bar_knob_and_no_pull
    bar = one('handle' => 'bar')
    assert_equal 3, bar[:parts].count { |pt| pt.role == 'handle' }
    assert_equal 148.0, moving(bar, 'Handle Grip').dx # 128 c-c + 20
    knob = one('handle' => 'knob')
    assert_equal ['knob'], knob[:parts].select { |pt| pt.shape == 'cylinder' }.map(&:role)
    assert_empty one('handle' => 'none')[:parts].select { |pt| %w[handle knob].include?(pt.role) }
  end

  def test_j_pull_front_is_a_profile_and_the_pull_edge_is_not_banded
    front = moving(one('handle' => 'j_pull'), 'Front')
    assert_equal 'profile', front.shape
    assert_equal 'x', front.axis
    assert_equal [1.5, 0.0, 1.5, 597.0, 18.0, 717.0], box_of(front)
    assert_equal({ l1: 0.0, l2: 1.0, w1: 1.0, w2: 1.0 }, front.info[:band])
    assert_equal DMP::Profiles.front_section('j_pull', 18.0, 717.0), front.profile
  end

  def test_shark_tooth_front_profile
    front = moving(one('handle' => 'shark_tooth'), 'Front')
    assert_equal [[0.0, 0.0], [18.0, 0.0], [18.0, 702.0], [3.0, 717.0], [0.0, 717.0]], front.profile
    assert_equal 0.0, front.info[:band][:l1]
  end

  def test_profile_pull_on_side_and_bottom_edges
    params = Calc.normalize('handle' => 'shark_tooth')
    left = Calc.front_parts('Door', 0, 0, 0, 400, 700, params, pull_edge: 'left', grain: 'z').first
    assert_equal 'z', left.axis
    assert_equal({ l1: 0.0, l2: 1.0, w1: 1.0, w2: 1.0 }, left.info[:band])
    bottom = Calc.front_parts('Door', 0, 0, 0, 400, 700, params, pull_edge: 'bottom', grain: 'z').first
    assert_equal 'x', bottom.axis
    assert_equal 0.0, bottom.info[:band][:w1]
    assert_equal [0.0, 700.0], bottom.profile.first
  end

  def test_edge_profile_reduces_the_front_by_20_and_adds_an_aluminium_pull
    d = one('handle' => 'edge_profile')
    assert_equal 697.0, moving(d, 'Front').dz
    pull = moving(d, 'Front - Profil handle')
    assert_equal 'aluminium', pull.info[:material]
    assert_equal [1.5, 0.0, 698.5, 597.0, 26.0, 20.0], box_of(pull)
    assert_equal 597.0, pull.info[:length]
  end

  def test_gola_reserves_30mm_and_adds_profiles
    result = drawers('handle' => 'gola', 'quantity' => '2')
    assert_equal [327.0, 327.0], result.map { |d| part(d[:parts], "Drawer #{d[:index]} - Front").dz }
    c = result[0][:fixed].find { |pt| pt.role == 'gola' }
    l = result[1][:fixed].find { |pt| pt.role == 'gola' }
    assert_equal 'Drawer 1 - Profil gola C', c.name
    assert_equal 'Drawer 2 - Profil gola L', l.name
    assert_equal [0.0, 0.0, 330.0, 600.0, 27.0, 30.0], box_of(c)
    assert_equal 690.0, l.z
    assert_equal 'profile', l.shape
  end

  def test_push_open_adds_a_latch_behind_the_box
    latch = fixed(one('handle' => 'push_open'), 'Push latch')
    assert_equal 'push_latch', latch.role
    assert_equal 518.0, latch.y
    assert_equal 294.0, latch.x
  end

  def test_shaker_and_glass_fronts_are_built_from_a_frame
    d = one('front_style' => 'shaker')
    names = d[:parts].map(&:name).grep(/Front - (Left|Right|Bottom|Top|Recessed)/)
    assert_equal ['Drawer 1 - Front - Left Stile', 'Drawer 1 - Front - Right Stile', 'Drawer 1 - Front - Bottom Rail',
                  'Drawer 1 - Front - Top Rail', 'Drawer 1 - Front - Recessed Panel'], names
    assert_equal [61.5, 12.0, 61.5, 477.0, 6.0, 597.0], box_of(moving(d, 'Front - Recessed Panel'))
    assert_equal 'glass', moving(one('front_style' => 'glass'), 'Front - Glass').role
  end

  def test_validation_errors
    bad = lambda do |params, pattern|
      error = assert_raises(ArgumentError, params.inspect) { Calc.normalize(params) }
      assert_match(pattern, error.message)
    end
    bad.call({ 'front_style' => 'shaker', 'handle' => 'j_pull' }, /slab/)
    bad.call({ 'front_style' => 'glass', 'handle' => 'shark_tooth' }, /slab/)
    bad.call({ 'front_style' => 'shaker', 'handle' => 'edge_profile' }, /slab/)
    bad.call({ 'slide_type' => 'undermount', 'drawer_bottom' => 'nailed' }, /undermount/)
    bad.call({ 'handle' => 'wavy' }, /handle/)
    bad.call({ 'slide_type' => 'magnetic' }, /slide_type/)
    bad.call({ 'slide_length' => 100 }, /150/)
    bad.call({ 'edge_thick' => 4 }, /3 mm/)
    bad.call({ 'groove_depth' => 15 }, /alur/)
    bad.call({ 'front_thickness' => 0 }, /front_thickness/)
    bad.call({ 'gap' => -1 }, /negatif/)
    bad.call({ 'gap' => Float::NAN }, /angka/)
    bad.call({ 'gap' => 'abc' }, /angka/)
    bad.call({ 'handle' => 'gola', 'gola_gap' => 0 }, /gola/)
    bad.call({ 'handle' => 'bar', 'handle_length' => 0 }, /handle/)
    bad.call({ 'slide_type' => 'custom', 'slide_clearance' => 0 }, /slide_clearance/)
    assert_raises(ArgumentError) { Calc.normalize('oops') }
  end

  def test_undermount_and_dado_with_groove_bottom_are_accepted
    assert_equal 'undermount', Calc.normalize('slide_type' => 'undermount')['slide_type']
    assert_equal 'dado', Calc.normalize('drawer_joint' => 'dado')['drawer_joint']
  end

  def test_space_validation
    assert_raises(ArgumentError) { Calc.compute({ 'width' => 40, 'depth' => 550, 'height' => 720 }, {}) }
    assert_raises(ArgumentError) { Calc.compute({ 'width' => 'x', 'depth' => 550, 'height' => 720 }, {}) }
    assert_raises(ArgumentError) { Calc.compute('space', {}) }
  end
end
