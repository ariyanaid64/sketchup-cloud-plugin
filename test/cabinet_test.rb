require 'minitest/autorun'
require_relative '../src/drawer_maker_pro/cabinet_calculator'

unless defined?(Sketchup)
  module Sketchup
    class Color
      def initialize(*); end
    end

    class Group; end

    class << self
      attr_accessor :active_model
    end
  end
end

class CabinetFakeEntities
  attr_reader :children

  def initialize
    @children = []
  end

  def add_group
    CabinetFakeGroup.new.tap { |group| @children << group }
  end

  def clear!
    @children.clear
  end
end

class CabinetFakeGroup < Sketchup::Group
  attr_accessor :name, :transformation
  attr_reader :entities, :unique

  def initialize
    @entities = CabinetFakeEntities.new
    @attributes = {}
    @transformation = :identity
  end

  def set_attribute(dictionary, key, value)
    (@attributes[dictionary] ||= {})[key] = value
  end

  def get_attribute(dictionary, key, default = nil)
    @attributes.fetch(dictionary, {}).fetch(key, default)
  end

  def make_unique
    @unique = true
  end
end

class CabinetFakeModel
  attr_reader :committed, :aborted, :operations

  def initialize
    @committed = 0
    @aborted = 0
    @operations = []
  end

  def start_operation(name, _transparent)
    @operations << name
  end

  def commit_operation
    @committed += 1
  end

  def abort_operation
    @aborted += 1
  end
end

require_relative '../src/drawer_maker_pro/builder'
require_relative '../src/drawer_maker_pro/cabinet_builder'

class CabinetCalculatorTest < Minitest::Test
  C = SketchupCloud::DrawerMakerPro::CabinetCalculator
  SPACE = { 'width' => 900.0, 'depth' => 600.0, 'height' => 2200.0 }.freeze

  def test_default_cabinet_has_carcass_doors_and_opening_descriptors
    result = C.compute(SPACE, {})
    assert_equal 1, result[:parts].count { |part| part.role == 'divider' }
    assert_equal 2, result[:parts].count { |part| part.role == 'shelf' }
    assert_equal 4, result[:doors].length
    assert_equal 4, result[:openings].length
    assert_equal 'Bay 1 / Space 1', result[:openings][0]['name']
    assert_equal({ 'width' => 423.0, 'depth' => 576.0, 'height' => 1023.0 }, result[:openings][0]['space'])
    assert_equal [18.0, 18.0, 118.0], result[:openings][0]['origin']
    assert_equal [18.0, 18.0, 1159.0], result[:openings][1]['origin']
    assert_equal({ 'width' => 423.0, 'depth' => 576.0, 'height' => 1023.0 }, result[:openings][1]['space'])
    floor = result[:parts].find { |part| part.name.end_with?('Floor') }
    assert_equal [18.0, 864.0, 594.0, 18.0], [floor.x, floor.dx, floor.dy, floor.dz]
    assert_equal 18.0, result[:parts].find { |part| part.role == 'shelf' }.y
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

  def test_fixed_column_widths_are_split_after_subtracting_dividers
    result = C.compute(SPACE, 'columns' => '420:426', 'door_mode' => 'none', 'shelves' => 0)
    assert_equal [420.0, 426.0], result[:openings].map { |opening| opening['space']['width'] }
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
    handles = left[:parts].select { |part| part.role == 'handle' }
    assert_equal 3, handles.length
    grip = handles.find { |part| part.name.end_with?('Handle Grip') }
    assert_equal 128.0, grip.dz
    assert handles.all? { |part| part.y + part.dy <= 0 }
    assert_operator left[:hinge_x], :<, right[:hinge_x]
    assert_equal 0.0, left[:hinge_y]
    assert_equal front_z, left[:hinge_z]
  end

  def test_single_and_no_door_modes
    single = C.compute(SPACE, 'columns' => '1', 'door_mode' => 'single', 'handle' => 'none')
    assert_equal 1, single[:doors].length
    assert_equal 4, single[:doors][0][:parts].count { |part| part.role == 'front' }
    none = C.compute(SPACE, 'door_mode' => 'none')
    assert_empty none[:doors]
    assert_equal 4, none[:openings].length
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

  def test_zero_height_plinth_has_no_zero_size_part
    result = C.compute(SPACE, 'plinth_height' => 0, 'columns' => '1')
    parts = result[:parts] + result[:doors].flat_map { |door| door[:parts] }

    refute parts.any? { |part| part.role == 'plinth' }
    parts.each do |part|
      assert [part.dx, part.dy, part.dz].all?(&:positive?), part.name
    end
  end

  def test_narrow_slab_door_handle_stays_inside_the_front
    narrow_space = { 'width' => 69.0, 'depth' => 600.0, 'height' => 800.0 }
    result = C.compute(narrow_space, 'columns' => '1', 'door_mode' => 'single',
                                   'front_style' => 'slab', 'handle' => 'bar', 'shelves' => 0)
    door = result[:doors].first
    front = door[:parts].find { |part| part.role == 'front' }
    handles = door[:parts].select { |part| part.role == 'handle' }

    assert_equal 30.0, front.dx
    assert_equal 3, handles.length
    handles.each do |part|
      assert_operator part.x, :>=, front.x
      assert_operator part.x + part.dx, :<=, front.x + front.dx
    end
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
      [{ 'panel_thickness' => 24 }, SPACE],
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

  def test_builder_create_and_rebuild_store_cabinet_metadata
    model = CabinetFakeModel.new
    Sketchup.active_model = model
    entities = CabinetFakeEntities.new
    builder = SketchupCloud::DrawerMakerPro::Builder
    original_add_part = builder.method(:add_part)
    added_parts = []
    builder.define_singleton_method(:add_part) do |target_entities, part, set_name|
      added_parts << [target_entities, part, set_name]
    end

    cabinet_builder = SketchupCloud::DrawerMakerPro::CabinetBuilder
    set = cabinet_builder.create(entities, :placed, SPACE,
                                 'columns' => '1', 'door_mode' => 'single', 'handle' => 'none', 'shelves' => 0)
    assert cabinet_builder.cabinet_set?(set)
    assert_equal :placed, set.transformation
    assert_equal 'cabinet_set', set.get_attribute(builder::DICT, 'type')
    assert_equal 1, JSON.parse(set.get_attribute(builder::DICT, 'openings')).length
    assert_equal 'Bay 1 / Space 1', JSON.parse(set.get_attribute(builder::DICT, 'openings')).first['name']
    door = set.entities.children.find { |child| child.get_attribute(builder::DICT, 'type') == 'door' }
    assert_equal :identity, door.transformation
    assert_equal 'left', door.get_attribute(builder::DICT, 'side')
    assert_in_delta 19.5, door.get_attribute(builder::DICT, 'hinge_x'), 0.001
    assert_equal 0.0, door.get_attribute(builder::DICT, 'hinge_y')
    assert door.get_attribute(builder::DICT, 'hinge_x').is_a?(Numeric)
    assert_operator added_parts.length, :>, 0
    assert_equal 1, model.committed
    refute_equal 0, model.operations.length

    set.set_attribute(builder::DICT, 'open', true)
    set.transformation = :keep_transform
    cabinet_builder.rebuild(set, 'columns' => '1', 'door_mode' => 'single', 'handle' => 'none', 'shelves' => 0)
    assert set.unique
    assert_equal :keep_transform, set.transformation
    assert_equal false, set.get_attribute(builder::DICT, 'open')
    assert_equal 2, model.committed
    assert_equal 0, model.aborted
  ensure
    builder.define_singleton_method(:add_part, original_add_part) if builder && original_add_part
  end
end
