require 'minitest/autorun'
require_relative '../src/drawer_maker_pro/cabinet_calculator'

class CabinetCalculatorTest < Minitest::Test
  C = SketchupCloud::DrawerMakerPro::CabinetCalculator
  SPACE = { 'width' => 900.0, 'depth' => 600.0, 'height' => 2200.0 }.freeze

  def test_default_cabinet_has_carcass_doors_and_opening_descriptors
    result = C.compute(SPACE, {})
    assert_equal 1, result[:parts].count { |part| part.role == 'divider' }
    assert_equal 2, result[:parts].count { |part| part.role == 'shelf' }
    assert_equal 4, result[:doors].length
    assert_equal 2, result[:openings].length
    assert_equal({ 'width' => 424.0, 'depth' => 594.0, 'height' => 2064.0 }, result[:openings][0]['space'])
    floor = result[:parts].find { |part| part.name.end_with?('Floor') }
    assert_equal [18.0, 864.0, 594.0, 18.0], [floor.x, floor.dx, floor.dy, floor.dz]
  end

  def test_column_split_subtracts_dividers_before_splitting
    result = C.compute(SPACE, 'columns' => '1:2:1', 'door_mode' => 'none', 'shelves' => 0)
    dividers = result[:parts].select { |part| part.role == 'divider' }
    assert_equal 2, dividers.length
    bays = result[:openings].map { |opening| opening['space']['width'] }
    assert_in_delta bays[0] * 2, bays[1], 0.001
    assert_in_delta bays[0], bays[2], 0.001
    assert_in_delta SPACE['width'] - 2 * 18.0 - 2 * 18.0, bays.sum, 0.001
  end

  def test_fixed_column_widths_use_calculator_split_rules
    result = C.compute(SPACE, 'columns' => '300:1', 'door_mode' => 'single', 'handle' => 'none', 'shelves' => 0)
    assert_in_delta 300.0, result[:openings][0]['space']['width']
    assert_equal 2, result[:doors].length
    assert_equal %w[left left], result[:doors].map { |door| door[:side] }
  end

  def test_door_gaps_hinge_edges_and_vertical_handles
    result = C.compute(SPACE, 'columns' => '1', 'shelves' => 0)
    doors = result[:doors]
    assert_equal %w[left right], doors.map { |door| door[:side] }
    left, right = doors
    left_front = left[:parts].select { |part| part.role == 'front' }
    right_front = right[:parts].select { |part| part.role == 'front' }
    left_x = left_front.map(&:x).min
    left_right = left_front.map { |part| part.x + part.dx }.max
    right_x = right_front.map(&:x).min
    right_edge = right_front.map { |part| part.x + part.dx }.max
    front_z = left_front.map(&:z).min
    front_top = left_front.map { |part| part.z + part.dz }.max
    assert_in_delta 1.5, left_x - 18.0, 0.001
    assert_in_delta left_right + 3.0, right_x, 0.001
    assert_in_delta right_edge + 1.5, 882.0, 0.001
    left_handle = left[:parts].find { |part| part.role == 'handle' }
    assert_equal front_top - front_z - 40.0, left_handle.dz
    assert_operator left_handle.dz, :>, 0
    assert_operator left[:hinge_x], :<, right[:hinge_x]
    assert_equal front_z, left[:hinge_z]
  end

  def test_single_and_no_door_modes
    single = C.compute(SPACE, 'columns' => '1', 'door_mode' => 'single', 'handle' => 'none')
    assert_equal 1, single[:doors].length
    assert_equal 4, single[:doors][0][:parts].count { |part| part.role == 'front' }
    none = C.compute(SPACE, 'door_mode' => 'none')
    assert_empty none[:doors]
    assert_equal 2, none[:openings].length
  end

  def test_shelves_are_evenly_spaced_in_each_bay
    result = C.compute(SPACE, 'columns' => '1', 'shelves' => 3, 'door_mode' => 'none')
    shelves = result[:parts].select { |part| part.role == 'shelf' }.sort_by(&:z)
    assert_equal 3, shelves.length
    gaps = shelves.each_cons(2).map { |a, b| b.z - a.z - a.dz }
    assert_in_delta gaps[0], gaps[1], 0.001
    floor_top = 100.0 + 18.0
    assert_operator shelves.first.z, :>, floor_top
    assert_operator shelves.last.z + shelves.last.dz, :<, SPACE['height'] - 18.0
  end

  def test_styles_are_passed_to_the_shared_front_helper_when_available
    return unless SketchupCloud::DrawerMakerPro::Calculator.respond_to?(:front_parts)

    result = C.compute(SPACE, 'columns' => '1', 'front_style' => 'glass', 'handle' => 'none')
    assert result[:doors][0][:parts].any? { |part| part.role == 'glass' || part.name.include?('Glass') }
  end

  def test_invalid_parameters_and_dimensions
    [
      [{ 'door_mode' => 'triple' }, SPACE],
      [{ 'front_style' => 'raised' }, SPACE],
      [{ 'handle' => 'knob' }, SPACE],
      [{ 'shelves' => 1.5 }, SPACE],
      [{ 'columns' => '1000:1' }, SPACE],
      [{ 'board_thickness' => Float::NAN }, SPACE],
      [{}, { 'width' => 30, 'depth' => 600, 'height' => 2200 }],
      [{ 'shelves' => 115 }, SPACE]
    ].each do |params, space|
      assert_raises(ArgumentError) { C.compute(space, params) }
    end
  end
end
