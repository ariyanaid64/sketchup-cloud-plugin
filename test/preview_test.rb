require_relative 'support/sketchup_fakes'

class PreviewTest < Minitest::Test
  include TestHelpers
  Preview = DMP::Preview
  DRAWER_SPACE = { 'width' => 600, 'depth' => 550, 'height' => 720 }.freeze
  CABINET_SPACE = { 'width' => 900, 'depth' => 560, 'height' => 870 }.freeze

  def test_drawer_payload_separates_fixed_and_moving_parts
    result = Preview.payload('drawer', DRAWER_SPACE, { 'quantity' => '2' }, 7)
    assert_equal 7, result[:requestId]
    assert_equal 2, result[:count]
    fixed, moving = result[:parts].partition { |pt| !pt[:moving] }
    assert_equal ['Drawer 1 - Slide L (kabinet)', 'Drawer 1 - Slide R (kabinet)',
                  'Drawer 2 - Slide L (kabinet)', 'Drawer 2 - Slide R (kabinet)'], fixed.map { |pt| pt[:name] }
    assert_equal [true], moving.map { |pt| pt[:moving] }.uniq
    front = moving.find { |pt| pt[:name] == 'Drawer 1 - Front' }
    assert_equal [1.5, 0.0, 1.5, 597.0, 18.0, 357.0, 'panel', 'box'], front.values_at(:x, :y, :z, :dx, :dy, :dz, :kind, :shape)
    assert_equal({ length: 597.0, width: 357.0, thickness: 18.0 }, front.slice(:length, :width, :thickness))
  end

  def test_cabinet_payload_counts_doors_and_drawers
    result = Preview.payload('cabinet', CABINET_SPACE, { 'bay_fronts' => 'door, drawers:3', 'front_style' => 'slab' }, 'r1')
    assert_equal 'r1', result[:requestId]
    assert_equal 4, result[:count]
    moving = result[:parts].select { |pt| pt[:moving] }
    fixed = result[:parts].reject { |pt| pt[:moving] }
    assert_includes moving.map { |pt| pt[:name] }, 'Cabinet Bay 1 Door 1'
    assert_includes moving.map { |pt| pt[:name] }, 'Cabinet Bay 2 Drawer 3 - Side L'
    assert_includes fixed.map { |pt| pt[:name] }, 'Cabinet - Side L'
    assert_equal 'profile', Preview.payload('cabinet', CABINET_SPACE, { 'handle' => 'gola' }, 1)[:parts].find { |pt| pt[:name] == 'Cabinet - Side L' }[:shape]
    assert_includes fixed.map { |pt| pt[:name] }, 'Cabinet Bay 2 Drawer 3 - Slide L (kabinet)'
  end

  def test_payload_is_json_serialisable
    payload = Preview.payload('cabinet', CABINET_SPACE, {}, nil)
    parsed = JSON.parse(JSON.generate(payload))
    assert_nil parsed['requestId']
    assert_equal payload[:parts].size, parsed['parts'].size
  end

  def test_invalid_params_raise_argument_error
    assert_raises(ArgumentError) { Preview.payload('drawer', DRAWER_SPACE, { 'handle' => 'wavy' }, 1) }
    assert_raises(ArgumentError) { Preview.payload('cabinet', CABINET_SPACE, { 'cabinet_type' => 'wall', 'handle' => 'gola' }, 1) }
  end
end
