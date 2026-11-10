require_relative 'support/sketchup_fakes'

# Motion only closes things: opening is done by the Dynamic Components Interact tool.
class MotionTest < Minitest::Test
  include TestHelpers
  Motion = DMP::Motion
  DICT = DMP::Builder::DICT
  DC = DMP::Builder::DC

  def setup
    @model = FakeSketchup::Model.new
    Sketchup.active_model = @model
  end

  def build_cabinet(params = {})
    DMP::CabinetBuilder.create(@model.entities, Geom::Transformation.new,
                               { 'width' => 900, 'depth' => 560, 'height' => 870 },
                               { 'front_style' => 'slab', 'bay_fronts' => 'door, drawers:2' }.merge(params))
  end

  def wrappers(set) = set.entities.grep(Sketchup::ComponentInstance).select { |i| %w[door drawer].include?(i.get_attribute(DICT, 'type')) }
  def mover_of(wrapper) = wrapper.definition.entities.grep(Sketchup::ComponentInstance).first

  def open!(wrapper, key, value)
    child = mover_of(wrapper)
    child.transformation = Geom::Transformation.new([:animated, value])
    child.set_attribute(DC, key, value)
    child
  end

  def test_close_all_resets_every_mover_and_zeroes_the_dynamic_attributes
    set = build_cabinet
    door, drawer1, drawer2 = wrappers(set)
    open!(door, 'rotz', -90.0)
    open!(drawer1, 'y', -45.0)
    open!(drawer2, 'y', -20.0)

    assert_equal 3, Motion.close_all(set)

    [door, drawer1, drawer2].each { |w| assert_equal Geom::Transformation.new, mover_of(w).transformation }
    assert_equal 0.0, mover_of(door).get_attribute(DC, 'rotz')
    assert_equal 0.0, mover_of(drawer1).get_attribute(DC, 'y')
    assert_equal 0.0, mover_of(drawer2).get_attribute(DC, 'y')
    assert_equal [[:start, 'Insert Cabinet', true], [:commit], [:start, 'Tutup semua pintu & laci', true], [:commit]],
                 @model.operations
    assert_equal 1, set.make_unique_calls
  end

  def test_close_all_does_not_invent_dynamic_attributes
    set = build_cabinet
    door = wrappers(set).first
    mover_of(door).transformation = Geom::Transformation.new([:animated])
    Motion.close_all(set)
    assert_nil mover_of(door).get_attribute(DC, 'rotz')
    assert_equal Geom::Transformation.new, mover_of(door).transformation
  end

  def test_close_all_leaves_wrappers_and_static_parts_alone
    set = build_cabinet
    before = wrappers(set).map(&:transformation)
    Motion.close_all(set)
    assert_equal before, wrappers(set).map(&:transformation)
  end

  def test_version_1_1_groups_return_to_their_closed_transform
    closed = [:original, 7, 11]
    legacy = FakeSketchup::Group.new
    legacy.set_attribute(DICT, 'type', 'drawer')
    legacy.set_attribute(DICT, 'closed_transform', closed)
    legacy.transformation = Geom::Transformation.new([:open])
    plain = FakeSketchup::Group.new
    plain.set_attribute(DICT, 'type', 'door')
    plain.transformation = Geom::Transformation.new([:untouched])
    set = FakeSketchup::Group.new
    set.entities.items.push(legacy, plain)

    assert_equal 2, Motion.close_all(set)
    assert_equal Geom::Transformation.new(closed), legacy.transformation
    assert_equal Geom::Transformation.new([:untouched]), plain.transformation
  end

  def test_locked_set_is_rejected_before_starting_an_operation
    set = build_cabinet
    set.instance_variable_set(:@locked, true)
    @model.operations.clear
    error = assert_raises(ArgumentError) { Motion.close_all(set) }
    assert_match(/terkunci/, error.message)
    assert_empty @model.operations
  end

  def test_set_without_movers_aborts_the_operation
    set = FakeSketchup::Group.new
    error = assert_raises(ArgumentError) { Motion.close_all(set) }
    assert_match(/tidak memiliki/, error.message)
    assert_equal [[:start, 'Tutup semua pintu & laci', true], [:abort]], @model.operations
  end

  def test_failure_while_closing_aborts_and_propagates
    set = build_cabinet
    @model.operations.clear
    wrappers(set).each { |w| open!(w, 'y', -1.0) }
    broken = mover_of(wrappers(set).first)
    broken.define_singleton_method(:transformation=) { |_| raise 'transform failed' }
    error = assert_raises(RuntimeError) { Motion.close_all(set) }
    assert_equal 'transform failed', error.message
    assert_equal [[:start, 'Tutup semua pintu & laci', true], [:abort]], @model.operations
  end

  def test_there_is_no_scripted_toggle_any_more
    refute_respond_to Motion, :toggle
  end
end
