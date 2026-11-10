require 'minitest/autorun'
require_relative '../src/drawer_maker_pro/calculator'

class DrawerVariantsTest < Minitest::Test
  C = SketchupCloud::DrawerMakerPro::Calculator
  SPACE = { 'width' => 600.0, 'depth' => 550.0, 'height' => 720.0 }.freeze

  def parts(params = {})
    C.compute(SPACE, { 'quantity' => '1', 'handle' => 'none' }.merge(params)).first[:parts]
  end

  def test_defaults_preserve_wooden_slab_geometry
    result = parts
    assert_equal %w[front side side sub_front back bottom], result.map(&:role)
    front = result.first
    assert_equal [1.5, 0.0, 1.5, 597.0, 18.0, 717.0],
                 [front.x, front.y, front.z, front.dx, front.dy, front.dz]
  end

  def test_metal_drawer_uses_thin_metal_sides
    metal_sides = parts('drawer_type' => 'metal').select { |part| part.role == 'metal_side' }
    assert_equal 2, metal_sides.length
    assert_equal [2.0], metal_sides.map(&:dx).uniq
  end

  def test_rail_drawer_has_lower_sides_and_gallery_rails
    result = parts('drawer_type' => 'rail', 'rail_height' => 90)
    sides = result.select { |part| part.role == 'side' }
    rails = result.select { |part| part.role == 'rail' }
    assert_equal 2, sides.length
    assert_equal [590.0], sides.map(&:dz).uniq
    assert_equal 2, rails.length
    assert_equal [90.0], rails.map(&:dz).uniq
  end

  def test_shaker_and_glass_faces_have_real_frame_and_panel_parts
    shaker = C.front_parts('Door', 0, 0, 0, 300, 500,
                           'front_style' => 'shaker', 'front_thickness' => 18,
                           'frame_width' => 50, 'panel_thickness' => 6)
    assert_equal %w[front front front front front_panel], shaker.map(&:role)
    panel = shaker.last
    assert_equal [200.0, 6.0, 400.0], [panel.dx, panel.dy, panel.dz]
    assert_equal 12.0, panel.y # recessed by front_thickness - panel_thickness

    glass = C.front_parts('Door', 0, 0, 0, 300, 500,
                          'front_style' => 'glass', 'frame_width' => 50)
    assert_equal 'glass', glass.last.role
    assert_equal 5, glass.length
  end

  def test_overlay_expands_only_at_outer_set_edges
    drawers = C.compute(SPACE, 'quantity' => '2', 'front_mode' => 'overlay',
                        'overlay' => 10, 'gap' => 2, 'handle' => 'none')
    faces = drawers.map { |drawer| drawer[:parts].find { |part| part.name.end_with?('Front') } }
    assert_in_delta 618.0, faces.first.dx
    assert_in_delta(-9.0, faces.first.z)
    assert_in_delta 368.0, faces.first.dz
    assert_in_delta 2.0, faces[1].z - (faces[0].z + faces[0].dz)
    assert_in_delta 9.0, faces.last.z + faces.last.dz - SPACE['height']
  end

  def test_invalid_enums_and_non_finite_or_negative_numbers_are_rejected
    [
      { 'drawer_type' => 'plastic' },
      { 'front_style' => 'raised' },
      { 'layout' => 'diagonal' },
      { 'front_mode' => 'partial' },
      { 'handle' => 'knob' },
      { 'gap' => -1 },
      { 'front_thickness' => 'NaN' },
      { 'board_thickness' => 'Infinity' },
      { 'metal_thickness' => 0, 'drawer_type' => 'metal' }
    ].each do |params|
      assert_raises(ArgumentError, params.inspect) { C.compute(SPACE, params) }
    end
    assert_raises(ArgumentError) do
      C.compute({ 'width' => 0, 'depth' => 550, 'height' => 720 }, 'handle' => 'none')
    end
  end

  def test_panel_frame_and_back_bounds_are_validated
    assert_raises(ArgumentError) { parts('front_style' => 'shaker', 'frame_width' => 300) }
    assert_raises(ArgumentError) { parts('bottom_raise' => 700) }
    assert_raises(ArgumentError) { parts('drawer_type' => 'rail', 'rail_height' => 700) }
  end

  def test_all_generated_part_dimensions_are_positive
    [
      parts,
      parts('drawer_type' => 'metal'),
      parts('drawer_type' => 'rail'),
      parts('front_style' => 'shaker')
    ].flatten.each do |part|
      assert [part.dx, part.dy, part.dz].all?(&:positive?), part.name
    end
  end
end
