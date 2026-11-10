require 'minitest/autorun'

module MotionTestSupport
  class Transformation
    attr_reader :operations
    def initialize(value = [])
      @operations = value.is_a?(Array) ? value.dup : [value]
    end
    def self.translation(vector) = new([[:translation, vector]])
    def self.rotation(origin, axis, angle) = new([[:rotation, origin, axis, angle]])
    def *(other) = self.class.new(@operations + other.operations)
    def to_a = @operations
    def ==(other) = other.is_a?(self.class) && to_a == other.to_a
  end

  class Group
    attr_accessor :fail_transform
    def initialize(type:, attributes: {}, transformation: Transformation.new([:closed]))
      @attrs = attributes.merge('type' => type)
      @transformation = transformation
    end
    def get_attribute(_dictionary, key, default = nil) = @attrs.fetch(key, default)
    def set_attribute(_dictionary, key, value) = @attrs[key] = value
    def transformation = @transformation
    def transformation=(value)
      raise RuntimeError, 'transform failed' if fail_transform
      @transformation = value
    end
  end

  class Entities
    def initialize(groups) = @groups = groups
    def grep(type) = @groups.grep(type)
  end

  class Set < Group
    attr_reader :entities, :make_unique_calls
    def initialize(groups, locked: false)
      super(type: 'set')
      @entities = Entities.new(groups)
      @locked = locked
      @make_unique_calls = 0
    end
    def locked? = @locked
    def make_unique
      @make_unique_calls += 1
      self
    end
  end

  class Model
    attr_reader :operations
    def initialize = @operations = []
    def start_operation(name, transparent) = @operations << [:start, name, transparent]
    def commit_operation = @operations << [:commit]
    def abort_operation = @operations << [:abort]
  end
end

unless defined?(Sketchup)
  module Sketchup
    class << self
      attr_accessor :active_model
    end
  end
end
Sketchup.const_set(:Group, MotionTestSupport::Group) unless Sketchup.const_defined?(:Group)
unless defined?(Geom)
  module Geom
    Transformation = MotionTestSupport::Transformation
  end
end
class Numeric
  def mm = to_f unless method_defined?(:mm)
  def degrees = to_f unless method_defined?(:degrees)
end

module SketchupCloud
  module DrawerMakerPro
    module Builder
      DICT = 'DrawerMakerPro'.freeze unless const_defined?(:DICT)
    end
  end
end
require_relative '../src/drawer_maker_pro/motion'

class MotionTest < Minitest::Test
  Motion = SketchupCloud::DrawerMakerPro::Motion
  DICT = SketchupCloud::DrawerMakerPro::Builder::DICT

  def setup
    @model = MotionTestSupport::Model.new
    Sketchup.active_model = @model
  end

  def test_open_close_restores_the_exact_saved_transform
    closed = MotionTestSupport::Transformation.new([:original_transform, 7, 11])
    drawer = moving_group('drawer', { 'travel' => 220.0 }, closed)
    set = MotionTestSupport::Set.new([drawer])
    Motion.toggle(set)
    assert_equal [[:translation, [0.0, -220.0, 0.0]]] + closed.to_a, drawer.transformation.to_a
    assert_equal closed.to_a, drawer.get_attribute(DICT, 'closed_transform')
    assert_equal true, set.get_attribute(DICT, 'open')
    Motion.toggle(set)
    assert_equal closed, drawer.transformation
    assert_equal false, set.get_attribute(DICT, 'open')
    assert_equal [[:start, 'Open / Close', true], [:commit], [:start, 'Open / Close', true], [:commit]], @model.operations
  end

  def test_doors_rotate_around_hinge_with_side_specific_ninety_degree_sign
    left = moving_group('door', { 'hinge_x' => 25, 'hinge_y' => 40, 'side' => 'left' })
    right = moving_group('door', { 'hinge_x' => 510, 'hinge_y' => 40, 'side' => 'right' })
    set = MotionTestSupport::Set.new([left, right])
    Motion.toggle(set)
    assert_equal [:rotation, [25.0, 40.0, 0], [0, 0, 1], -90.0], left.transformation.operations.first
    assert_equal [:rotation, [510.0, 40.0, 0], [0, 0, 1], 90.0], right.transformation.operations.first
  end

  def test_drawer_travel_is_local_negative_y
    drawer = moving_group('drawer', { 'travel' => 375.5 })
    Motion.toggle(MotionTestSupport::Set.new([drawer]))
    assert_equal [:translation, [0.0, -375.5, 0.0]], drawer.transformation.operations.first
  end

  def test_exception_aborts_operation_and_propagates
    drawer = moving_group('drawer', { 'travel' => 100 })
    drawer.fail_transform = true
    set = MotionTestSupport::Set.new([drawer])
    error = assert_raises(RuntimeError) { Motion.toggle(set) }
    assert_equal 'transform failed', error.message
    assert_equal [[:start, 'Open / Close', true], [:abort]], @model.operations
  end

  def test_toggle_makes_set_unique_before_mutating_its_geometry
    drawer = moving_group('drawer', { 'travel' => 100 })
    set = MotionTestSupport::Set.new([drawer])
    Motion.toggle(set)
    assert_equal 1, set.make_unique_calls
    assert_equal true, set.get_attribute(DICT, 'open')
    assert_equal [:commit], @model.operations.last
  end

  def test_locked_set_is_rejected_before_starting_operation
    set = MotionTestSupport::Set.new([moving_group('drawer', { 'travel' => 100 })], locked: true)
    assert_raises(ArgumentError) { Motion.toggle(set) }
    assert_empty @model.operations
  end

  private

  def moving_group(type, attributes = {}, transformation = MotionTestSupport::Transformation.new([:closed]))
    MotionTestSupport::Group.new(type: type, attributes: attributes, transformation: transformation)
  end
end
