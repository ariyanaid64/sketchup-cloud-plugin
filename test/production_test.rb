require_relative 'support/sketchup_fakes'

class ProductionTest < Minitest::Test
  include TestHelpers
  P = DMP::Production
  Profiles = DMP::Profiles

  def area(points)
    sum = 0.0
    points.each_with_index do |(x1, y1), i|
      x2, y2 = points[(i + 1) % points.size]
      sum += x1 * y2 - x2 * y1
    end
    sum / 2.0
  end

  def assert_valid_polygon(points)
    assert_operator points.size, :>=, 3
    points.each_cons(2) { |a, b| refute_equal a, b, 'duplicate consecutive points' }
    refute_equal points.first, points.last
    refute_in_delta 0.0, area(points), 1e-6
  end

  def test_hinge_count_thresholds
    assert_equal 2, P.hinge_count(900)
    assert_equal 3, P.hinge_count(900.1)
    assert_equal 3, P.hinge_count(1600)
    assert_equal 4, P.hinge_count(1601)
    assert_equal 4, P.hinge_count(2000)
    assert_equal 5, P.hinge_count(2000.1)
  end

  def test_hinge_positions_are_100_from_the_ends_and_evenly_spread
    assert_equal [100.0, 637.0], P.hinge_positions(737)
    assert_equal [100.0, 500.0, 900.0], P.hinge_positions(1000)
    assert_equal [100.0, 600.0, 1100.0, 1600.0], P.hinge_positions(1700)
  end

  def test_hinge_edge_distance_shrinks_for_short_doors
    # 200 mm high: 100 mm would exceed height / 4, so 50 mm is used.
    assert_equal [50.0, 150.0], P.hinge_positions(200)
  end

  def test_connector_positions
    assert_equal [50.0, 280.0, 510.0], P.connector_positions(560)
    assert_equal [50.0, 150.0], P.connector_positions(200)
    assert_equal [40.0], P.connector_positions(80)
    positions = P.connector_positions(1000)
    assert_equal 50.0, positions.first
    assert_equal 950.0, positions.last
    positions.each_cons(2) { |a, b| assert_operator b - a, :<=, 300.0 + 1e-9 }
  end

  def test_slide_length_uses_requested_or_longest_standard_that_fits
    assert_equal [250.0, 300.0, 350.0, 400.0, 450.0, 500.0, 550.0, 600.0, 650.0], P::SLIDE_LENGTHS
    assert_equal 500.0, P.slide_length(522, 0)
    assert_equal 650.0, P.slide_length(2000, 0)
    assert_equal 450.0, P.slide_length(522, 450)
    assert_raises(ArgumentError) { P.slide_length(522, 600) }
    error = assert_raises(ArgumentError) { P.slide_length(200, 0) }
    assert_match(/250/, error.message)
  end

  def test_panel_edge_banding_reduces_cut_size
    pt = P.panel('Front', 'front', 1.5, 0, 1.5, 597, 18, 237, len_axis: 'x', band: { l1: 1, l2: 1, w1: 1, w2: 1 })
    assert_equal 597.0, pt.info[:finish_l]
    assert_equal 237.0, pt.info[:finish_w]
    assert_equal 18.0, pt.info[:thickness]
    assert_equal 595.0, pt.info[:cut_l]
    assert_equal 235.0, pt.info[:cut_w]
  end

  def test_panel_band_edges_map_to_length_and_width
    # l1 + l2 run along the length (reduce width); w1 + w2 are the short edges.
    pt = P.panel('Side', 'side', 0, 0, 0, 18, 560, 770, len_axis: 'z', band: { l1: 1.0 })
    assert_equal 770.0, pt.info[:cut_l]
    assert_equal 559.0, pt.info[:cut_w]
    pt = P.panel('Shelf', 'shelf', 0, 0, 0, 400, 300, 18, len_axis: 'x', band: { l1: 0.4, w1: 2.0 })
    assert_equal 398.0, pt.info[:cut_l]
    assert_close 299.6, pt.info[:cut_w]
  end

  def test_panel_rejects_zero_or_negative_dimensions
    assert_raises(ArgumentError) { P.panel('Zero', 'x', 0, 0, 0, 0, 18, 100, len_axis: 'z') }
    assert_raises(ArgumentError) { P.panel('Neg', 'x', 0, 0, 0, 10, -18, 100, len_axis: 'z') }
    assert_raises(ArgumentError) { P.panel('NaN', 'x', 0, 0, 0, Float::NAN, 18, 100, len_axis: 'z') }
  end

  def test_part_kind_and_cut_size
    hw = P.hardware('Hinge', 'hinge', 'desc', 0, 0, 0, 35, 13, 35, qty: 2, length: 10)
    assert hw.hardware?
    assert_equal 'hardware', hw.kind
    assert_equal({ length: 35.0, width: 35.0, thickness: 13.0 }, hw.cut_size)
    panel = P.panel('P', 'p', 0, 0, 0, 100, 18, 50, len_axis: 'x')
    refute panel.hardware?
    assert_equal 'box', panel.to_h[:shape]
  end

  def test_cylinder_origin_is_the_bounding_box_corner
    cyl = P.cylinder('Pin', 'pin', 'Pin', [100, 50, 20], 'x', 5.0, 12.0)
    assert_equal [100.0, 47.5, 17.5, 12.0, 5.0, 5.0], box_of(cyl)
    assert_equal 'cylinder', cyl.shape
    assert_equal 'x', cyl.axis
    assert_equal [97.5, 50.0, 17.5, 5.0, 12.0, 5.0], box_of(P.cylinder('P', 'p', 'd', [100, 50, 20], 'y', 5.0, 12.0))
    assert_equal [97.5, 47.5, 20.0, 5.0, 5.0, 12.0], box_of(P.cylinder('P', 'p', 'd', [100, 50, 20], 'z', 5.0, 12.0))
  end

  def test_j_pull_section_stays_inside_the_front_and_is_valid
    section = Profiles.front_section('j_pull', 18.0, 717.0)
    assert_valid_polygon section
    assert_equal [0.0, 0.0], section.first
    assert_equal [0.0, 717.0], section.last
    section.each do |u, v|
      assert_operator u, :>=, -1e-9
      assert_operator u, :<=, 18.0 + 1e-9
      assert_operator v, :>=, -1e-9
      assert_operator v, :<=, 717.0 + 1e-9
    end
    # The grip lip is 5 mm at the pull edge; the finger scoop is 25 mm deep.
    assert_includes section, [5.0, 705.0]
    assert_in_delta 5.0, section[-2][0], 1e-9
  end

  def test_shark_tooth_section_is_a_bevel
    section = Profiles.front_section('shark_tooth', 18.0, 717.0)
    assert_equal [[0.0, 0.0], [18.0, 0.0], [18.0, 702.0], [3.0, 717.0], [0.0, 717.0]], section
    assert_valid_polygon section
    # 45 degree bevel: 15 mm in depth over 15 mm along the front.
    assert_in_delta 15.0, 18.0 - 3.0, 1e-9
    assert_in_delta 15.0, 717.0 - 702.0, 1e-9
  end

  def test_profile_sections_reject_fronts_that_are_too_small
    assert_raises(ArgumentError) { Profiles.front_section('j_pull', 18.0, 40.0) }
    assert_raises(ArgumentError) { Profiles.front_section('shark_tooth', 18.0, 30.0) }
    assert_raises(ArgumentError) { Profiles.front_section('wavy', 18.0, 500.0) }
    assert_valid_polygon Profiles.front_section('j_pull', 18.0, 45.0)
  end

  def test_edge_profile_and_gola_sections
    edge = Profiles.edge_profile_section(18.0)
    assert_valid_polygon edge
    assert_equal 20.0, edge.map { |_, v| v }.max
    %w[L C].each do |kind|
      section = Profiles.gola_section(kind, 30.0)
      assert_valid_polygon section
      assert_equal 30.0, section.map { |_, v| v }.max
      assert_equal 27.0, section.map { |u, _| u }.max
    end
    assert_equal 6, Profiles.gola_section('L', 30.0).size
    assert_equal 8, Profiles.gola_section('C', 30.0).size
  end

  def test_place_maps_the_pull_edge_section_onto_the_front
    section = [[0.0, 0.0], [18.0, 10.0]]
    assert_equal ['x', [[0.0, 0.0], [18.0, 10.0]]], Profiles.place(section, 'top', 600, 700)
    assert_equal ['x', [[0.0, 700.0], [18.0, 690.0]]], Profiles.place(section, 'bottom', 600, 700)
    assert_equal ['z', [[0.0, 0.0], [10.0, 18.0]]], Profiles.place(section, 'right', 600, 700)
    assert_equal ['z', [[600.0, 0.0], [590.0, 18.0]]], Profiles.place(section, 'left', 600, 700)
    assert_raises(ArgumentError) { Profiles.place(section, 'diagonal', 600, 700) }
  end

  def test_hinge_and_slide_catalogues
    assert_equal %w[ball_bearing roller undermount], P::SLIDE_CLEARANCE.keys
    assert_equal [12.7, 12.5, 5.0], P::SLIDE_CLEARANCE.values
    assert_equal %w[full_overlay half_overlay inset], P::HINGE_NAMES.keys
    assert_equal 37.0, P::SYSTEM_LINE
    assert_equal 35.0, P::CUP_DIAMETER
  end
end
