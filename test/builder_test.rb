require_relative 'support/sketchup_fakes'

# Builder / CabinetBuilder against the fake SketchUp object model.
class BuilderTest < Minitest::Test
  include TestHelpers
  DICT = DMP::Builder::DICT
  DC = DMP::Builder::DC
  SPACE = { 'width' => 600, 'depth' => 550, 'height' => 720 }.freeze
  CAB_SPACE = { 'width' => 900, 'depth' => 560, 'height' => 870 }.freeze

  def setup
    @model = FakeSketchup::Model.new
    Sketchup.active_model = @model
  end

  def identity = Geom::Transformation.new

  def create_drawers(params = {})
    DMP::Builder.create(@model.entities, identity, SPACE, params)
  end

  def create_cabinet(params = {}, space = CAB_SPACE)
    DMP::CabinetBuilder.create(@model.entities, identity, space, params)
  end

  def movers(set, kind)
    set.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICT, 'type') == kind }
  end

  def definition_named(name) = @model.definitions.find { |d| d.name == name }

  def test_drawer_set_metadata_and_undo_operation
    set = create_drawers('quantity' => '2')
    assert DMP::Builder.drawer_set?(set)
    refute DMP::CabinetBuilder.cabinet_set?(set)
    assert_equal 'Drawer set (2)', set.name
    assert_equal 'set', set.get_attribute(DICT, 'type')
    assert_equal SPACE, JSON.parse(set.get_attribute(DICT, 'space'))
    assert_equal '2', JSON.parse(set.get_attribute(DICT, 'params'))['quantity']
    assert_equal [[:start, 'Insert Drawers', true], [:commit]], @model.operations
  end

  def test_drawer_is_a_dynamic_component_that_slides_out_on_click
    set = create_drawers('quantity' => '2')
    drawers = movers(set, 'drawer')
    assert_equal ['Drawer 1', 'Drawer 2'], drawers.map(&:name)
    assert_equal [450.0, 450.0], drawers.map { |d| d.get_attribute(DICT, 'travel') }

    wrapper = drawers.first.definition
    mover_def = definition_named('Drawer 1 (gerak)')
    assert_equal 'Drawer 1', wrapper.name
    [wrapper, mover_def].each do |definition|
      assert_equal true, definition.get_attribute(DICT, 'owned')
      assert_equal 'CENTIMETERS', definition.get_attribute(DC, '_lengthunits')
      assert_equal 1.0, definition.get_attribute(DC, '_formatversion')
      assert_equal 'Drawer 1', definition.get_attribute(DC, 'name')
    end
    assert_nil wrapper.get_attribute(DC, 'onclick')
    # 450 mm = 45 cm, negative Y = out of the cabinet.
    assert_equal 'ANIMATE("y",0,-45)', mover_def.get_attribute(DC, 'onclick')
    assert_equal 'onClick', mover_def.get_attribute(DC, '_onclick_label')
    assert_equal 1.0, mover_def.get_attribute(DC, '_hasbehaviors')

    child = wrapper.entities.grep(Sketchup::ComponentInstance).first
    assert_equal 'mover', child.get_attribute(DICT, 'type')
    assert_same mover_def, child.definition
    assert_equal identity, child.transformation
    assert_equal [:translation, [0.0, 0.0, 0.0]], drawers.first.transformation.to_a
  end

  def test_drawer_parts_live_in_the_moving_definition_and_slide_hardware_is_static
    set = create_drawers('quantity' => '1', 'handle' => 'none')
    mover_def = definition_named('Drawer 1 (gerak)')
    names = mover_def.entities.map(&:name)
    assert_includes names, 'Drawer 1 - Front'
    assert_includes names, 'Drawer 1 - Slide L (laci)'
    refute_includes names, 'Drawer 1 - Slide L (kabinet)'
    static = set.entities.grep(Sketchup::Group).find { |g| g.get_attribute(DICT, 'type') == 'fixed' }
    assert_equal ['Drawer 1 - Slide L (kabinet)', 'Drawer 1 - Slide R (kabinet)'], static.entities.map(&:name)
  end

  def test_panels_are_unique_groups_with_cut_list_attributes
    create_drawers('quantity' => '1')
    front = definition_named('Drawer 1 (gerak)').entities.find { |e| e.name == 'Drawer 1 - Front' }
    assert_kind_of Sketchup::Group, front
    assert_equal 'part', front.get_attribute(DICT, 'type')
    assert_equal 'front', front.get_attribute(DICT, 'role')
    assert_equal 'panel', front.get_attribute(DICT, 'kind')
    assert_equal 'Drawer', front.get_attribute(DICT, 'set')
    assert_equal [597.0, 717.0, 18.0, 595.0, 715.0],
                 %w[finish_l finish_w thickness cut_l cut_w].map { |k| front.get_attribute(DICT, k) }
    assert_equal({ 'l1' => 1.0, 'l2' => 1.0, 'w1' => 1.0, 'w2' => 1.0 }, JSON.parse(front.get_attribute(DICT, 'band')))
    assert_equal 'x', front.get_attribute(DICT, 'grain')
    assert_equal 'DMP Front', front.material.name
    assert_equal [192, 153, 108], front.material.color.rgb
    # Geometry: base face in XY pushed up by dz (717 mm), in inches.
    assert_equal 1, front.entities.faces.size
    assert_in_delta 717.mm, front.entities.faces.first.pushed, 1e-9
  end

  def test_profile_front_extrudes_the_section_along_its_axis
    create_drawers('quantity' => '1', 'handle' => 'shark_tooth')
    front = definition_named('Drawer 1 (gerak)').entities.find { |e| e.name == 'Drawer 1 - Front' }
    face = front.entities.faces.first
    assert_equal 5, face.points.size
    assert_in_delta 597.mm, face.pushed, 1e-9 # extruded across the width (axis x)
    assert_in_delta 1.5.mm, face.points.first.x, 1e-9
  end

  def test_hardware_is_shared_between_instances_via_component_definitions
    create_cabinet('front_style' => 'slab')
    cups = @model.definitions.select { |d| d.name.start_with?('DMP Engsel sendok 35 mm full overlay') && d.get_attribute(DICT, 'hw_key').include?('cylinder') }
    assert_equal 1, cups.size
    assert_equal 4, cups.first.instances.size # 2 doors x 2 hinges
    assert_match(/cylinder/, cups.first.get_attribute(DICT, 'hw_key'))
    instance = cups.first.instances.first
    assert_equal 'hinge', instance.get_attribute(DICT, 'role')
    assert_equal 'hardware', instance.get_attribute(DICT, 'kind')
    assert_equal 1.0, instance.get_attribute(DICT, 'qty')
    assert_equal 'DMP Metal', instance.material.name
    assert_equal 1, cups.first.entities.faces.size
  end

  def test_second_build_reuses_existing_hardware_definitions
    create_cabinet('front_style' => 'slab')
    before = @model.definitions.count { |d| d.get_attribute(DICT, 'hw_key') }
    create_cabinet('front_style' => 'slab')
    after = @model.definitions.count { |d| d.get_attribute(DICT, 'hw_key') }
    assert_equal before, after
  end

  def test_slide_members_report_fractional_quantities
    create_drawers('quantity' => '1')
    slide = @model.definitions.find { |d| d.name.start_with?('DMP Rel ball bearing') }
    quantities = slide.instances.map { |i| i.get_attribute(DICT, 'qty') }.sort
    assert_equal [0.0, 0.0, 0.5, 0.5], quantities
  end

  def test_cabinet_set_metadata
    set = create_cabinet
    assert DMP::CabinetBuilder.cabinet_set?(set)
    assert_equal 'Cabinet set', set.name
    assert_equal 'cabinet_set', set.get_attribute(DICT, 'type')
    assert_equal 4, JSON.parse(set.get_attribute(DICT, 'openings')).size
    assert_equal CAB_SPACE, JSON.parse(set.get_attribute(DICT, 'space'))
    assert_equal [[:start, 'Insert Cabinet', true], [:commit]], @model.operations
    carcass = set.entities.grep(Sketchup::Group).first
    assert_equal 'Cabinet Carcass', carcass.name
    assert_equal 'carcass', carcass.get_attribute(DICT, 'type')
  end

  def test_door_dynamic_component_rotates_about_the_hinge_side
    set = create_cabinet('front_style' => 'slab')
    left, right = movers(set, 'door')
    assert_equal ['Cabinet Bay 1 Door 1', 'Cabinet Bay 2 Door 1'], [left.name, right.name]
    assert_equal %w[left right], [left, right].map { |d| d.get_attribute(DICT, 'side') }
    assert_equal [110.0, 110.0], [left, right].map { |d| d.get_attribute(DICT, 'angle') }
    assert_equal 'ANIMATE("rotz",0,-110)', definition_named('Cabinet Bay 1 Door 1 (gerak)').get_attribute(DC, 'onclick')
    assert_equal 'ANIMATE("rotz",0,110)', definition_named('Cabinet Bay 2 Door 1 (gerak)').get_attribute(DC, 'onclick')
    # The wrapper is placed at the hinge pivot on the front face (x 1.5 / 898.5, y -18).
    assert_in_delta 1.5.mm, left.transformation.to_a[1][0], 1e-9
    assert_in_delta(-18.mm, left.transformation.to_a[1][1], 1e-9)
    assert_in_delta 898.5.mm, right.transformation.to_a[1][0], 1e-9
  end

  def test_door_parts_are_positioned_relative_to_the_hinge_pivot
    create_cabinet('front_style' => 'slab', 'handle' => 'none')
    mover_def = definition_named('Cabinet Bay 1 Door 1 (gerak)')
    front = mover_def.entities.find { |e| e.name == 'Cabinet Bay 1 Door 1' }
    # Door front at x 1.5 y -18 with the pivot at the same x/y: group faces start at 0.
    assert_in_delta 0.0, front.entities.faces.first.points.first.x, 1e-9
    assert_in_delta 0.0, front.entities.faces.first.points.first.y, 1e-9
    assert_in_delta 101.5.mm, front.entities.faces.first.points.first.z, 1e-9
  end

  def test_cabinet_drawers_open_with_their_travel
    set = create_cabinet(DMP::CabinetCalculator::DEFAULTS.merge('bay_fronts' => 'drawers:2', 'columns' => '1'))
    assert_equal 2, movers(set, 'drawer').size
    onclick = definition_named('Cabinet Bay 1 Drawer 1 (gerak)').get_attribute(DC, 'onclick')
    assert_equal 'ANIMATE("y",0,-45)', onclick
  end

  def test_rebuild_replaces_geometry_and_removes_orphaned_definitions
    set = create_drawers('quantity' => '3')
    owned_before = @model.definitions.select { |d| d.get_attribute(DICT, 'owned') }
    assert_equal 6, owned_before.size
    DMP::Builder.rebuild(set, 'quantity' => '1')
    owned_after = @model.definitions.select { |d| d.get_attribute(DICT, 'owned') }
    assert_equal 2, owned_after.size
    assert(owned_after.all? { |d| !d.instances.empty? }, 'owned definitions without instances were left behind')
    assert_equal 6, @model.definitions.removed.size
    assert_equal 'Drawer set (1)', set.name
    assert_equal 1, movers(set, 'drawer').size
    assert_equal 1, set.make_unique_calls
    assert_equal [:start, 'Edit Drawers', true], @model.operations[2]
    assert_equal '1', JSON.parse(set.get_attribute(DICT, 'params'))['quantity']
    assert_equal SPACE, JSON.parse(set.get_attribute(DICT, 'space'))
  end

  def test_cabinet_rebuild_keeps_stored_space_and_updates_params
    set = create_cabinet('front_style' => 'slab')
    DMP::CabinetBuilder.rebuild(set, 'front_style' => 'slab', 'bay_fronts' => 'drawers:3')
    assert_equal 0, movers(set, 'door').size
    assert_equal 6, movers(set, 'drawer').size # 2 bays x 3
    assert_equal CAB_SPACE, JSON.parse(set.get_attribute(DICT, 'space'))
    assert(@model.definitions.select { |d| d.get_attribute(DICT, 'owned') }.none? { |d| d.instances.empty? })
    assert_equal 'Edit Cabinet', @model.operations[2][1]
  end

  def test_invalid_params_fail_before_touching_the_model
    assert_raises(ArgumentError) { create_drawers('handle' => 'wavy') }
    assert_raises(ArgumentError) { create_cabinet('cabinet_type' => 'wall', 'handle' => 'gola') }
    assert_empty @model.operations
    assert_empty @model.entities.items
  end

  def test_operation_aborts_and_reraises
    error = assert_raises(RuntimeError) { DMP::Builder.operation('X') { raise 'boom' } }
    assert_equal 'boom', error.message
    assert_equal [[:start, 'X', true], [:abort]], @model.operations
  end

  def test_material_palette_is_created_once
    create_cabinet
    names = @model.materials.map(&:name)
    assert_equal names.uniq, names
    assert_includes names, 'DMP Carcass'
    assert_includes names, 'DMP Back'
    assert_equal 0.35, DMP::Builder.material_for(DMP::Production.panel('G', 'glass', 0, 0, 0, 10, 6, 10, len_axis: 'x', material: 'glass')).alpha
  end

  def test_gola_profile_hardware_is_extruded_from_its_section
    create_cabinet('handle' => 'gola', 'top_type' => 'rails', 'front_style' => 'slab')
    gola = @model.definitions.find { |d| d.name == 'DMP Profil gola L aluminium' }
    refute_nil gola
    face = gola.entities.faces.first
    assert_equal 6, face.points.size
    assert_in_delta 900.mm, face.pushed, 1e-9
    assert_equal 900.0, gola.instances.first.get_attribute(DICT, 'length')
    assert_equal 'DMP Aluminium', gola.instances.first.material.name
  end
end
