require 'json'
require 'minitest/autorun'
require_relative '../src/drawer_maker_pro/calculator'
require_relative '../src/drawer_maker_pro/cabinet_calculator'

module DialogTestSupport
  class Model
    attr_accessor :active_path
    attr_reader :selection
    def initialize
      @selection = Selection.new
    end
  end

  class Selection
    include Enumerable
    def initialize = @items = []
    def each(&block) = @items.each(&block)
    def clear = @items.clear
    def add(item) = @items << item
    end
  end

  class Entity
    def initialize
      @attrs = {}
      @valid = true
      @locked = false
    end
    def get_attribute(dict, key, default = nil) = @attrs.fetch([dict, key], default)
    def set_attribute(dict, key, value) = @attrs[[dict, key]] = value
    def valid? = @valid
    def locked? = @locked
    def invalidate = @valid = false
    def lock = @locked = true
  end

  class HtmlDialog
    STYLE_DIALOG = :dialog
    attr_reader :callbacks, :scripts
    attr_accessor :closed
    def initialize(*)
      @callbacks = {}
      @scripts = []
    end
    def set_file(*) = nil
    def add_action_callback(name, &block) = @callbacks[name] = block
    def execute_script(script) = @scripts << script
    def set_on_closed(&block) = @on_closed = block
    def show = nil
    def close
      return if @closed
      @closed = true
      @on_closed&.call
    end
    def call(name, payload = nil) = @callbacks.fetch(name).call(nil, payload)
  end
end

unless defined?(Sketchup)
  module Sketchup
    class << self
      attr_accessor :active_model
      def test_defaults = (@defaults ||= {})
      def read_default(section, key, default = nil) = test_defaults.fetch([section, key], default)
      def write_default(section, key, value) = test_defaults[[section, key]] = value
    end
  end
end
unless defined?(UI)
  module UI
    HtmlDialog = DialogTestSupport::HtmlDialog
  end
end

module SketchupCloud
  module DrawerMakerPro
    module Builder
      DICT = 'DrawerMakerPro'.freeze unless const_defined?(:DICT)
      class << self
        attr_accessor :calls, :failure
        def create(*args)
          calls << [:create, *args]
          raise failure if failure
          :drawer_set
        end
        def rebuild(*args)
          calls << [:rebuild, *args]
          raise failure if failure
          :rebuilt_drawer_set
        end
      end
    end
    module CabinetBuilder
      class << self
        attr_accessor :calls, :failure
        def create(*args)
          calls << [:create, *args]
          raise failure if failure
          :cabinet_set
        end
        def rebuild(*args)
          calls << [:rebuild, *args]
          raise failure if failure
          :rebuilt_cabinet_set
        end
      end
    end
  end
end
require_relative '../src/drawer_maker_pro/dialog'

class DialogTest < Minitest::Test
  DMP = SketchupCloud::DrawerMakerPro
  SPACE = { 'width' => 600.0, 'depth' => 550.0, 'height' => 720.0 }.freeze
  CABINET_SPACE = { 'width' => 900.0, 'depth' => 600.0, 'height' => 2200.0 }.freeze

  def setup
    @model = DialogTestSupport::Model.new
    Sketchup.active_model = @model
    Sketchup.test_defaults.clear
    DMP::Builder.calls = []
    DMP::Builder.failure = DMP::CabinetBuilder.failure = nil
    DMP::CabinetBuilder.calls = []
    DMP::Dialog.instance_variable_set(:@instances, [])
  end

  def test_ready_loads_legacy_drawer_preferences_with_defaults
    legacy = { 'quantity' => '2', 'handle' => 'none', 'drawer_type' => 'metal' }
    Sketchup.test_defaults[[DMP::Dialog::PREF_KEY, 'params']] = JSON.generate(legacy)
    dialog = open_dialog(entities: Object.new, transformation: :transform, space: SPACE)
    dialog.call('ready')
    state = payload(dialog, 'DMP.load')
    assert_equal 'drawer', state['kind']
    assert_equal SPACE, state['space']
    assert_equal '2', state.dig('params', 'quantity')
    assert_equal 'metal', state.dig('params', 'drawer_type')
    assert_equal 15.0, state.dig('params', 'board_thickness')
  end

  def test_ready_pushes_normalized_cabinet_data
    dialog = open_dialog(kind: 'cabinet', entities: Object.new, transformation: :transform, space: CABINET_SPACE)
    dialog.call('ready')
    state = payload(dialog, 'DMP.load')
    assert_equal 'cabinet', state['kind']
    assert_equal CABINET_SPACE, state['space']
    assert_equal DMP::CabinetCalculator::DEFAULTS, state['params']
  end

  def test_drawer_preview_serializes_real_parts_and_request_id
    dialog = open_dialog(entities: Object.new, transformation: :transform, space: SPACE)
    params = { 'quantity' => '1', 'handle' => 'none' }
    dialog.call('preview', JSON.generate('requestId' => 73, 'params' => params))
    result = payload(dialog, 'DMP.preview')
    expected = DMP::Calculator.compute(SPACE, params).flat_map { |d| d[:parts] }.map(&:to_h)
    expected = JSON.parse(JSON.generate(expected))
    assert_equal 73, result['requestId']
    assert_equal 1, result['count']
    assert_equal expected, result['parts']
  end

  def test_cabinet_preview_serializes_carcass_and_door_parts
    dialog = open_dialog(kind: 'cabinet', entities: Object.new, transformation: :transform, space: CABINET_SPACE)
    params = { 'columns' => '1', 'shelves' => 0, 'handle' => 'none' }
    dialog.call('preview', JSON.generate('requestId' => 'cab-9', 'space' => CABINET_SPACE, 'params' => params))
    result = payload(dialog, 'DMP.preview')
    plan = DMP::CabinetCalculator.compute(CABINET_SPACE, params)
    expected = plan[:parts] + plan[:doors].flat_map { |door| door[:parts] }
    assert_equal 'cab-9', result['requestId']
    assert_equal plan[:openings].length, result['count']
    assert_equal JSON.parse(JSON.generate(expected.map(&:to_h))), result['parts']
  end

  def test_create_dispatches_drawer_builder_and_uses_drawer_target_size
    entities = Object.new
    dialog = open_dialog(entities: entities, transformation: :transform, space: SPACE)
    params = { 'quantity' => '1', 'handle' => 'none' }
    dialog.call('create', JSON.generate('space' => { 'width' => 1 }, 'params' => params))
    assert_equal [[:create, entities, :transform, SPACE, params]], DMP::Builder.calls
    assert_equal [:drawer_set], @model.selection.to_a
    assert dialog.closed
  end

  def test_create_dispatches_cabinet_builder_with_client_space
    entities = Object.new
    requested = { 'width' => 900, 'depth' => 600, 'height' => 2200 }
    dialog = open_dialog(kind: 'cabinet', entities: entities, transformation: :transform, space: :ignored)
    params = { 'columns' => '1', 'shelves' => 0 }
    dialog.call('create', JSON.generate('space' => requested, 'params' => params))
    assert_equal [[:create, entities, :transform, requested, params]], DMP::CabinetBuilder.calls
    assert_empty DMP::Builder.calls
    assert_equal [:cabinet_set], @model.selection.to_a
  end

  def test_drawer_edit_rebuild_uses_stored_size_not_client_size
    set = stored_set
    dialog = open_dialog(set: set)
    params = { 'quantity' => '2', 'handle' => 'none' }
    dialog.call('create', JSON.generate('space' => { 'width' => 1, 'depth' => 1, 'height' => 1 }, 'params' => params))
    assert_equal [[:rebuild, set, params]], DMP::Builder.calls
    assert_empty DMP::CabinetBuilder.calls
    assert_equal [:rebuilt_drawer_set], @model.selection.to_a
  end

  def test_cabinet_edit_dispatches_to_cabinet_builder
    set = stored_set(kind: 'cabinet', space: CABINET_SPACE, params: DMP::CabinetCalculator::DEFAULTS)
    dialog = open_dialog(set: set, kind: 'cabinet')
    params = { 'columns' => '1', 'shelves' => 0, 'handle' => 'none' }
    dialog.call('create', JSON.generate('space' => { 'width' => 1 }, 'params' => params))
    assert_equal [[:rebuild, set, params]], DMP::CabinetBuilder.calls
  end

  def test_deleted_or_locked_edit_targets_fail_without_rebuild
    [->(set) { set.invalidate }, ->(set) { set.lock }].each do |change|
      set = stored_set
      change.call(set)
      dialog = open_dialog(set: set)
      dialog.call('create', valid_payload)
      assert_empty DMP::Builder.calls
      assert_script_error(dialog)
    end
  end

  def test_changed_model_or_active_edit_context_fails_without_rebuild
    [-> { Sketchup.active_model = DialogTestSupport::Model.new }, -> { @model.active_path = [:changed] }].each do |change|
      Sketchup.active_model = @model
      @model.active_path = [:original]
      dialog = open_dialog(set: stored_set)
      change.call
      dialog.call('create', valid_payload)
      assert_empty DMP::Builder.calls
      assert_script_error(dialog)
    end
  end

  def test_failed_creation_resets_busy_and_reports_error
    DMP::Builder.failure = RuntimeError.new('builder failed')
    dialog = open_dialog(entities: Object.new, transformation: :transform, space: SPACE)
    dialog.call('create', valid_payload)
    assert_script_error(dialog)
    assert dialog.scripts.any? { |s| s.start_with?('DMP.busy(false); DMP.error(') }
    refute dialog.closed
  end

  def test_cancel_closes_dialog
    dialog = open_dialog(entities: Object.new, transformation: :transform, space: SPACE)
    dialog.call('cancel')
    assert dialog.closed
  end

  def test_open_releases_instances_after_close
    instance = DMP::Dialog.open(entities: Object.new, transformation: :transform, space: SPACE)
    instances = DMP::Dialog.instance_variable_get(:@instances)
    assert_includes instances, instance
    instance.instance_variable_get(:@dialog).close
    refute_includes instances, instance
  end

  private

  def open_dialog(target)
    instance = DMP::Dialog.new(target)
    instance.show
    instance.instance_variable_get(:@dialog)
  end

  def stored_set(space: SPACE, params: DMP::Calculator::DEFAULTS, **_options)
    set = DialogTestSupport::Entity.new
    set.set_attribute(DMP::Builder::DICT, 'space', JSON.generate(space))
    set.set_attribute(DMP::Builder::DICT, 'params', JSON.generate(params))
    set
  end

  def valid_payload
    JSON.generate('params' => { 'quantity' => '1', 'handle' => 'none' })
  end

  def payload(dialog, method)
    script = dialog.scripts.reverse.find { |s| s.start_with?("#{method}(") }
    JSON.parse(script.match(/\A#{Regexp.escape(method)}\((.*)\)\z/)[1])
  end

  def assert_script_error(dialog)
    assert dialog.scripts.any? { |s| s.start_with?('DMP.busy(false); DMP.error(') }
  end
end
