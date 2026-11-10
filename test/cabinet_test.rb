require_relative 'support/sketchup_fakes'

# Cabinet layout: carcass, joints, doors, hinges, drawers and gola (millimetres).
class CabinetCalculatorTest < Minitest::Test
  include TestHelpers
  Cab = DMP::CabinetCalculator
  SPACE = { width: 900, depth: 560, height: 870 }.freeze
  GOLA = { 'bay_fronts' => 'door, drawers:3', 'handle' => 'gola', 'front_style' => 'slab', 'top_type' => 'rails' }.freeze

  def plan(params = {}, space = SPACE) = Cab.compute(space, params)
  def find(plan_, name) = part(plan_[:parts], name)
  def roles(list, role) = list.select { |pt| pt.role == role }
  def hinge_cups(door) = door[:parts].select { |pt| pt.role == 'hinge' }
  def error_for(params, space = SPACE) = assert_raises(ArgumentError, params.inspect) { Cab.compute(space, params) }

  # ---- carcass --------------------------------------------------------

  def test_default_carcass_structure
    r = plan
    counts = r[:parts].map(&:role).tally
    assert_equal 2, counts['side']
    assert_equal 1, counts['bottom']
    assert_equal 1, counts['top']
    assert_equal 1, counts['divider']
    assert_equal 1, counts['back']
    assert_equal 4, counts['plinth']
    assert_equal 2, counts['shelf'] # one adjustable shelf per door bay
    assert_equal 8, counts['shelf_pin']
    assert_equal 2, r[:doors].size
    assert_empty r[:drawers]
    assert_equal 4, r[:openings].size
    assert_equal [18.0, 0.0, 118.0], r[:openings][0]['origin']
    assert_equal({ 'width' => 423.0, 'depth' => 544.0, 'height' => 358.0 }, r[:openings][0]['space'])
  end

  def test_sides_bottom_top_and_divider_geometry
    r = plan
    assert_equal [0.0, 0.0, 100.0, 18.0, 560.0, 770.0], box_of(find(r, 'Cabinet - Side L'))
    assert_equal [882.0, 0.0, 100.0, 18.0, 560.0, 770.0], box_of(find(r, 'Cabinet - Side R'))
    assert_equal [18.0, 0.0, 100.0, 864.0, 560.0, 18.0], box_of(find(r, 'Cabinet - Bottom'))
    assert_equal [18.0, 0.0, 852.0, 864.0, 560.0, 18.0], box_of(find(r, 'Cabinet - Top'))
    assert_equal [441.0, 0.0, 118.0, 18.0, 544.0, 734.0], box_of(find(r, 'Cabinet - Divider 1'))
    side = find(r, 'Cabinet - Side L')
    assert_equal 'z', side.info[:len_axis]
    assert_equal({ l1: 1.0, l2: 0.0, w1: 0.0, w2: 0.0 }, side.info[:band])
    assert_equal 770.0, side.info[:cut_l]
    assert_equal 559.0, side.info[:cut_w]
  end

  def test_plinth_base
    r = plan
    assert_equal [0.0, 50.0, 0.0, 900.0, 18.0, 100.0], box_of(find(r, 'Cabinet - Plinth Front'))
    assert_equal [0.0, 522.0, 0.0, 900.0, 18.0, 100.0], box_of(find(r, 'Cabinet - Plinth Back'))
    assert_equal [0.0, 68.0, 0.0, 18.0, 454.0, 100.0], box_of(find(r, 'Cabinet - Plinth Side L'))
  end

  def test_leg_counts_follow_the_width
    assert_equal [4, 6, 8], [600, 900, 1500].map { |w|
      roles(plan({ 'base_type' => 'legs', 'columns' => '1' }, { width: w, depth: 560, height: 870 }).fetch(:parts), 'leg').size
    }
    legs = roles(plan({ 'base_type' => 'legs', 'columns' => '1' })[:parts], 'leg')
    assert(legs.all? { |l| l.shape == 'cylinder' && l.axis == 'z' && l.dz == 100.0 && l.dx == 40.0 })
    assert_equal 'Kaki adjustable 100 mm', legs.first.info[:desc]
    assert_equal ['Cabinet - Plinth Front'], plan('base_type' => 'legs')[:parts].select { |pt| pt.role == 'plinth' }.map(&:name)
  end

  def test_no_base_puts_the_carcass_on_the_floor
    r = plan('base_type' => 'none', 'columns' => '1')
    assert_equal [0.0, 0.0, 0.0, 18.0, 560.0, 870.0], box_of(find(r, 'Cabinet - Side L'))
    refute(r[:parts].any? { |pt| %w[plinth leg].include?(pt.role) })
  end

  def test_back_modes
    groove = find(plan, 'Cabinet - Back')
    assert_equal [11.0, 544.0, 111.0, 878.0, 6.0, 748.0], box_of(groove)
    assert_equal 'x', groove.info[:len_axis] # 878 wide > 748 high

    rabbet = find(plan('back_mode' => 'rabbet'), 'Cabinet - Back')
    assert_equal [10.5, 554.0, 110.5, 879.0, 6.0, 749.0], box_of(rabbet)

    nailed = plan('back_mode' => 'nailed')
    assert_equal [1.0, 554.0, 101.0, 898.0, 6.0, 768.0], box_of(find(nailed, 'Cabinet - Back'))
    # Sides stop where the nailed back starts.
    assert_equal 554.0, find(nailed, 'Cabinet - Side L').dy
  end

  def test_top_rails_replace_the_top_panel
    r = plan('top_type' => 'rails')
    assert_equal [18.0, 0.0, 852.0, 864.0, 100.0, 18.0], box_of(find(r, 'Cabinet - Top Rail Front'))
    assert_equal [18.0, 460.0, 852.0, 864.0, 100.0, 18.0], box_of(find(r, 'Cabinet - Top Rail Back'))
    refute(r[:parts].any? { |pt| pt.role == 'top' })
  end

  def test_connector_counts_per_joint_type
    counts = %w[confirmat minifix dowel dado].to_h do |joint|
      list = roles(plan({ 'carcass_joint' => joint, 'columns' => '1', 'shelves' => 0 })[:parts], 'connector')
      [joint, [list.size, list.sum { |c| c.info[:qty] }]]
    end
    # bottom + top, 3 positions along 560 mm on each side
    assert_equal [12, 12], counts['confirmat']
    assert_equal [12, 12], counts['dowel']
    # minifix = cam (1) + bolt (qty 0) + dowel (1) per position
    assert_equal [36, 24], counts['minifix']
    assert_equal [0, 0], counts['dado']
  end

  def test_dado_joint_extends_horizontals_into_the_sides
    r = plan('carcass_joint' => 'dado', 'columns' => '1')
    assert_equal [10.0, 0.0, 100.0, 880.0, 560.0, 18.0], box_of(find(r, 'Cabinet - Bottom'))
    assert_equal [10.0, 0.0, 852.0, 880.0, 560.0, 18.0], box_of(find(r, 'Cabinet - Top'))
    assert_empty roles(r[:parts], 'connector')
    divider = plan('carcass_joint' => 'dado')
    assert_equal [441.0, 0.0, 110.0, 18.0, 544.0, 750.0], box_of(find(divider, 'Cabinet - Divider 1'))
  end

  def test_divider_connectors_are_vertical_into_bottom_and_top
    r = plan
    divider = r[:parts].select { |pt| pt.role == 'connector' && pt.name.include?('Divider 1') }
    assert_equal 12, divider.size # 3 positions x (cam + bolt) x 2 faces
    bolts = divider.select { |pt| pt.axis == 'z' }
    assert_equal 6, bolts.size
    assert_equal [0, 0, 0, 0, 0, 0], bolts.map { |b| b.info[:qty] }
  end

  def test_wall_cabinet_has_hangers_and_hangs_from_the_top_edge
    r = plan({ 'cabinet_type' => 'wall', 'columns' => '1', 'base_type' => 'none' }, { width: 600, depth: 320, height: 700 })
    hangers = roles(r[:parts], 'hanger')
    assert_equal [[18.0, 254.0, 622.0, 60.0, 50.0, 60.0], [522.0, 254.0, 622.0, 60.0, 50.0, 60.0]], hangers.map { |h| box_of(h) }
    assert_empty roles(plan({ 'columns' => '1' })[:parts], 'hanger')
  end

  def test_shelves_adjustable_and_fixed
    r = plan('shelves' => 2, 'columns' => '1')
    shelves = roles(r[:parts], 'shelf')
    assert_equal 2, shelves.size
    assert_equal 8, roles(r[:parts], 'shelf_pin').size # 2 front + 2 rear pins per side
    assert_equal [19.0, 20.0, 350.667, 862.0, 522.0, 18.0], box_of(shelves.first)

    fixed = plan('shelves' => 2, 'columns' => '1', 'shelf_type' => 'fixed')
    first = roles(fixed[:parts], 'shelf').first
    assert_equal [18.0, 20.0, 350.667, 864.0, 524.0, 18.0], box_of(first)
    assert_empty roles(fixed[:parts], 'shelf_pin')
    assert_operator roles(fixed[:parts], 'connector').size, :>, 0
  end

  def test_fixed_shelves_use_dado_housings
    r = plan('shelves' => 1, 'columns' => '1', 'shelf_type' => 'fixed', 'carcass_joint' => 'dado')
    assert_equal [10.0, 20.0, 476.0, 880.0, 524.0, 18.0], box_of(roles(r[:parts], 'shelf').first)
  end

  # ---- doors / hinges -------------------------------------------------

  def test_full_overlay_doors_cover_the_sides_and_half_the_divider
    r = plan('front_style' => 'slab', 'handle' => 'none')
    left, right = r[:doors]
    assert_equal [1.5, -18.0, 101.5, 447.0, 18.0, 767.0], box_of(left[:parts][0])
    assert_equal [451.5, -18.0, 101.5, 447.0, 18.0, 767.0], box_of(right[:parts][0])
    assert_close 3.0, right[:parts][0].x - (left[:parts][0].x + left[:parts][0].dx)
  end

  def test_half_overlay_doors_cover_half_the_side_thickness
    r = plan('front_style' => 'slab', 'handle' => 'none', 'door_fit' => 'half_overlay')
    left = r[:doors][0]
    assert_equal 10.5, left[:parts][0].x
    assert_equal 110.5, left[:parts][0].z
    assert_equal 749.0, left[:parts][0].dz
    assert_equal 10.5, left[:hinge_x]
  end

  def test_inset_doors_sit_in_the_opening_with_reveal_gaps
    r = plan('front_style' => 'slab', 'handle' => 'none', 'door_fit' => 'inset', 'columns' => '1', 'door_mode' => 'single')
    door = r[:doors][0][:parts][0]
    assert_equal [19.5, 0.0, 119.5, 861.0, 18.0, 731.0], box_of(door)
  end

  def test_inset_double_doors_hinges_plates_and_shelf_setback
    r = plan('bay_fronts' => 'door2', 'door_fit' => 'inset', 'handle' => 'bar')
    assert_equal 4, r[:doors].size
    first = r[:doors][0][:parts]
    stile = first.find { |pt| pt.name.end_with?('Left Stile') }
    assert_equal [19.5, 0.0, 119.5, 60.0, 18.0, 731.0], box_of(stile)
    right_edge = first.find { |pt| pt.name.end_with?('Right Stile') }
    assert_close 208.5, right_edge.x + right_edge.dx - stile.x
    cups = r[:doors].flat_map { |door| hinge_cups(door) }
    assert_equal 8, cups.size
    assert_equal ['Engsel sendok 35 mm inset (crank 18)'], cups.map { |c| c.info[:desc] }.uniq
    plates = roles(r[:parts], 'hinge_plate')
    assert_equal 8, plates.size
    # 37 mm system line + 18 mm front thickness for inset doors.
    assert_equal [55.0], plates.map { |pl| (pl.y + 22.0).round(3) }.uniq
    shelf = find(r, 'Cabinet - Bay 1 Shelf 1')
    assert_equal 38.0, shelf.y # front thickness 18 + setback 20
  end

  def test_full_overlay_plate_sits_on_the_37mm_line
    r = plan('front_style' => 'slab', 'handle' => 'none')
    plates = roles(r[:parts], 'hinge_plate')
    assert_equal [37.0], plates.map { |pl| pl.y + 22.0 }.uniq
    assert_equal [44.0, 10.0, 32.0], [plates[0].dy, plates[0].dx, plates[0].dz]
  end

  def test_hinge_type_follows_the_hinge_side_panel
    # Door in the middle bay hinges on a divider: half overlay even in full_overlay.
    r = plan({ 'columns' => '3', 'bay_fronts' => 'door1', 'front_style' => 'slab', 'handle' => 'none' })
    types = r[:doors].map { |d| [d[:side], hinge_cups(d).map { |c| c.info[:desc] }.uniq] }
    assert_equal [['left', ['Engsel sendok 35 mm full overlay (lurus / crank 0)']],
                  ['left', ['Engsel sendok 35 mm half overlay (crank 9,5)']],
                  ['right', ['Engsel sendok 35 mm full overlay (lurus / crank 0)']]], types
    half = plan({ 'door_fit' => 'half_overlay' })
    assert_equal ['Engsel sendok 35 mm half overlay (crank 9,5)'], half[:doors].flat_map { |d| hinge_cups(d) }.map { |c| c.info[:desc] }.uniq
  end

  def test_hinge_cup_positions_and_mounting_plates
    r = plan(GOLA)
    door = r[:doors][0]
    cups = hinge_cups(door)
    assert_equal [[5.5, -12.5, 184.0, 35.0, 13.0, 35.0], [5.5, -12.5, 721.0, 35.0, 13.0, 35.0]], cups.map { |c| box_of(c) }
    # 4 mm default cup distance + 17.5 mm radius = 21.5 from the door edge.
    assert_equal 21.5, cups[0].x + 17.5 - door[:parts][0].x
    # Cup centre z is 100 mm from the bottom of the door.
    assert_equal 100.0, cups[0].z + 17.5 - door[:parts][0].z
    assert_equal 'cylinder', cups[0].shape
    plates = roles(r[:parts], 'hinge_plate')
    assert_equal 2, plates.size
    assert_equal [18.0, 18.0], plates.map(&:x)
  end

  def test_cup_distance_moves_the_cup
    cup = hinge_cups(plan('cup_distance' => 7.0, 'front_style' => 'slab')[:doors][0]).first
    assert_equal 8.5, cup.x
  end

  def test_hinge_count_grows_with_door_height
    counts = [800, 1500, 2100].map do |h|
      d = plan({ 'columns' => '1', 'door_mode' => 'single', 'front_style' => 'slab', 'handle' => 'none', 'base_type' => 'none' },
               { width: 500, depth: 560, height: h })[:doors][0]
      [d[:parts][0].dz, hinge_cups(d).size]
    end
    assert_equal [[797.0, 2], [1497.0, 3], [2097.0, 5]], counts
  end

  def test_door_hinge_sides
    double = plan('columns' => '1', 'door_mode' => 'double')
    assert_equal %w[left right], double[:doors].map { |d| d[:side] }
    assert_equal [1.5, 898.5], double[:doors].map { |d| d[:hinge_x] }
    assert_equal [-18.0, -18.0], double[:doors].map { |d| d[:hinge_y] }
    assert_equal %w[left right], plan[:doors].map { |d| d[:side] }
    # A single leaf in a lone column hinges left; in the last bay of several it hinges right.
    assert_equal ['left'], plan('columns' => '1', 'door_mode' => 'single')[:doors].map { |d| d[:side] }
    assert_equal %w[left left right], plan('columns' => '3', 'bay_fronts' => 'door1')[:doors].map { |d| d[:side] }
    assert_equal [110.0] * 2, plan[:doors].map { |d| d[:angle] }
    assert_equal [75.0], plan({ 'columns' => '1', 'door_mode' => 'single', 'hinge_angle' => 75 })[:doors].map { |d| d[:angle] }
  end

  def test_auto_door_mode_splits_wide_bays
    assert_equal 1, plan({ 'columns' => '1' }, { width: 500, depth: 560, height: 870 })[:doors].size
    assert_equal 2, plan({ 'columns' => '1' }, { width: 900, depth: 560, height: 870 })[:doors].size
  end

  def test_open_bays_have_no_doors_but_keep_openings
    r = plan('bay_fronts' => 'open, door')
    assert_equal 1, r[:doors].size
    assert_equal ['Bay 1 / Space 1', 'Bay 1 / Space 2', 'Bay 2 / Space 1', 'Bay 2 / Space 2'], r[:openings].map { |o| o['name'] }
    assert_empty plan('door_mode' => 'none')[:doors]
  end

  def test_vertical_handles_and_pull_edges
    tall = plan({ 'cabinet_type' => 'tall', 'columns' => '1', 'door_mode' => 'single' }, { width: 600, depth: 560, height: 2100 })
    door = tall[:doors][0]
    assert_equal 4, hinge_cups(door).size
    grip = door[:parts].find { |pt| pt.name.end_with?('Handle Grip') }
    assert_equal [10.0, 10.0, 148.0], [grip.dx, grip.dy, grip.dz]
    assert_operator grip.x, :>, door[:parts][0].x + 400 # near the free (right) edge
  end

  def test_narrow_door_rejects_oversized_handle
    error_for({ 'columns' => '1', 'door_mode' => 'single', 'handle_length' => 800 }, { width: 400, depth: 560, height: 870 })
  end

  # ---- drawers --------------------------------------------------------

  def test_drawer_bay_fronts_boxes_and_slides
    r = plan(GOLA)
    assert_equal ['Cabinet Bay 2 Drawer 3', 'Cabinet Bay 2 Drawer 2', 'Cabinet Bay 2 Drawer 1'], r[:drawers].map { |d| d[:name] }
    assert_equal [450.0] * 3, r[:drawers].map { |d| d[:travel] }
    front = r[:drawers][0][:parts][0]
    assert_equal [451.5, -18.0, 101.5], [front.x, front.y, front.z]
    assert_equal 447.0, front.dx
    assert_close 223.667, front.dz
    side = part(r[:drawers][0][:parts], 'Cabinet Bay 2 Drawer 3 - Side L')
    assert_equal [471.7, 0.0, 133.0, 15.0, 500.0], box_of(side).first(5)
    # Slide members: cabinet member at the opening wall, drawer member inside it (12.7 clearance in total).
    cab_l = find(r, 'Cabinet Bay 2 Drawer 3 - Slide L (kabinet)')
    cab_r = find(r, 'Cabinet Bay 2 Drawer 3 - Slide R (kabinet)')
    assert_equal 459.0, cab_l.x
    assert_close 875.65, cab_r.x
    drawer_l = part(r[:drawers][0][:parts], 'Cabinet Bay 2 Drawer 3 - Slide L (laci)')
    drawer_r = part(r[:drawers][0][:parts], 'Cabinet Bay 2 Drawer 3 - Slide R (laci)')
    assert_close 465.35, drawer_l.x
    assert_close 869.3, drawer_r.x
    assert_equal 500.0, cab_l.dy
  end

  def test_drawer_stack_is_contiguous_and_spec_is_top_down
    r = plan('bay_fronts' => 'drawers:1:2', 'columns' => '1', 'front_style' => 'slab', 'handle' => 'none')
    top, bottom = r[:drawers].map { |d| d[:parts][0] }
    assert_equal ['Cabinet Bay 1 Drawer 2', 'Cabinet Bay 1 Drawer 1'], r[:drawers].map { |d| d[:name] }
    assert_operator top.dz, :>, bottom.dz # drawer 2 is the big lower one
  end

  def test_gola_notches_sides_and_adds_top_profile
    r = plan(GOLA)
    side = find(r, 'Cabinet - Side L')
    assert_equal 'profile', side.shape
    assert_equal 'x', side.axis
    assert_equal [[0.0, 0.0], [560.0, 0.0], [560.0, 770.0], [27.0, 770.0], [27.0, 740.0], [0.0, 740.0]], side.profile
    assert_equal [18.0, 27.0, 852.0, 864.0, 100.0, 18.0], box_of(find(r, 'Cabinet - Top Rail Front'))
    gola = find(r, 'Cabinet - Profil gola L 1')
    assert_equal [0.0, 0.0, 840.0, 900.0, 27.0, 30.0], box_of(gola)
    door = r[:doors][0][:parts][0]
    assert_equal [1.5, -18.0, 101.5, 447.0, 18.0, 737.0].first(3), box_of(door).first(3)
    assert_equal 737.0, door.dz
    assert_equal 'aluminium', gola.info[:material]
    # Drawers get a C channel above them; the top drawer is covered by the L profile.
    channels = r[:parts].select { |pt| pt.role == 'gola' && pt.name.include?('gola C') }
    assert_equal 2, channels.size
  end

  def test_gola_with_full_top_notches_the_top_panel_front
    r = plan('handle' => 'gola', 'top_type' => 'full', 'columns' => '1')
    assert_equal [18.0, 27.0, 852.0, 864.0, 533.0, 18.0], box_of(find(r, 'Cabinet - Top'))
  end

  def test_gola_with_inset_fronts_has_no_side_notch
    r = plan('handle' => 'gola', 'door_fit' => 'inset', 'columns' => '1')
    assert_nil find(r, 'Cabinet - Side L').shape
    gola = find(r, 'Cabinet - Profil gola L 1')
    assert_equal [18.0, 0.0, 822.0, 864.0, 27.0, 30.0], box_of(gola)
    assert_equal 701.0, r[:doors][0][:parts][0].dz
  end

  def test_profile_pull_doors_use_profile_fronts
    r = plan('front_style' => 'slab', 'handle' => 'shark_tooth', 'columns' => '1', 'door_mode' => 'single')
    front = r[:doors][0][:parts][0]
    assert_equal 'profile', front.shape
    assert_equal 'x', front.axis # base cabinets pull from the top edge
    wall = plan({ 'front_style' => 'slab', 'handle' => 'j_pull', 'cabinet_type' => 'wall', 'columns' => '1', 'door_mode' => 'single',
                  'base_type' => 'none' }, { width: 500, depth: 320, height: 700 })
    assert_equal 'profile', wall[:doors][0][:parts][0].shape
    assert_equal 0.0, wall[:doors][0][:parts][0].info[:band][:w1] # bottom edge is the machined pull edge
  end

  # ---- validation -----------------------------------------------------

  def test_gola_requires_a_top_pull_edge
    error = error_for('cabinet_type' => 'wall', 'handle' => 'gola')
    assert_match(/Gola/, error.message)
    assert_equal 'gola', Cab.normalize('cabinet_type' => 'wall', 'handle' => 'gola', 'pull_edge' => 'top')['handle']
    assert_equal 'gola', Cab.normalize('cabinet_type' => 'base', 'handle' => 'gola')['handle']
  end

  def test_profile_pulls_require_slab_fronts
    %w[j_pull shark_tooth edge_profile].each do |handle|
      error = error_for('handle' => handle, 'front_style' => 'shaker')
      assert_match(/slab/, error.message)
    end
  end

  def test_undermount_requires_a_grooved_bottom
    assert_match(/undermount/, error_for('slide_type' => 'undermount', 'drawer_bottom' => 'nailed').message)
  end

  def test_bay_fronts_validation
    assert_match(/harus sama/, error_for('bay_fronts' => 'door,door,door').message)
    assert_match(/tidak dikenal/, error_for('bay_fronts' => 'door,banana').message)
    assert_match(/Nilai pembagian/, error_for('bay_fronts' => 'drawers:a').message)
    assert_equal ['door', 'drawers', 'open'], Cab.bay_fronts(Cab.normalize('bay_fronts' => 'pintu, laci:2, terbuka', 'columns' => '3'), 3).map { |b| b[:type] }
    assert_equal [{ type: 'door', leaves: 1 }, { type: 'door', leaves: 2 }],
                 Cab.bay_fronts(Cab.normalize('bay_fronts' => 'door1,door2'), 2)
    assert_equal [{ type: 'door', leaves: 2 }] * 2, Cab.bay_fronts(Cab.normalize('bay_fronts' => 'door2'), 2)
  end

  def test_cup_distance_and_hinge_angle_ranges
    assert_match(/3–7 mm/, error_for('cup_distance' => 2.9).message)
    assert_match(/3–7 mm/, error_for('cup_distance' => 7.1).message)
    assert_equal 3.0, Cab.normalize('cup_distance' => 3)['cup_distance']
    assert_equal 7.0, Cab.normalize('cup_distance' => 7)['cup_distance']
    assert_match(/30–170/, error_for('hinge_angle' => 20).message)
    assert_match(/30–170/, error_for('hinge_angle' => 175).message)
  end

  def test_other_parameter_validation
    assert_match(/tidak dikenal/, assert_raises(ArgumentError) { Cab.normalize('bogus' => 1) }.message)
    assert_raises(ArgumentError) { Cab.normalize('oops') }
    assert_raises(ArgumentError) { Cab.normalize('name' => ' ') }
    assert_raises(ArgumentError) { Cab.normalize('door_fit' => 'overhang') }
    assert_raises(ArgumentError) { Cab.normalize('board_thickness' => 0) }
    assert_raises(ArgumentError) { Cab.normalize('shelves' => -1) }
    assert_raises(ArgumentError) { Cab.normalize('shelves' => 1.5) }
    assert_raises(ArgumentError) { Cab.normalize('gap' => Float::INFINITY) }
    assert_match(/30 mm/, error_for('plinth_height' => 20).message)
    assert_equal 0.0, Cab.normalize('base_type' => 'none', 'plinth_height' => 0)['plinth_height']
    assert_match(/alur/, error_for('back_groove_depth' => 18).message)
    assert_match(/dado/, error_for('carcass_joint' => 'dado', 'dado_depth' => 10).message)
  end

  def test_space_validation
    assert_raises(ArgumentError) { Cab.compute({ width: 100, depth: 560, height: 870 }, {}) }
    assert_raises(ArgumentError) { Cab.compute({ width: 900, depth: 560 }, {}) }
    assert_raises(ArgumentError) { Cab.compute({ width: 'x', depth: 560, height: 870 }, {}) }
    assert_raises(ArgumentError) { Cab.compute('space', {}) }
    assert_raises(ArgumentError) { Cab.compute({ width: 900, depth: 560, height: 870 }, 'columns' => '9', 'bay_fronts' => 'door') }
  end

  def test_column_specs
    assert_equal 3, Cab.column_count('3')
    assert_equal 3, Cab.column_count('1:1:2')
    assert_equal 2, Cab.column_count('300:500')
    r = plan('columns' => '1:2', 'bay_fronts' => 'door1')
    assert_equal 2, r[:doors].size
    assert_close 2.0, r[:openings][2]['space']['width'] / r[:openings][0]['space']['width'], 1e-6
  end
end
