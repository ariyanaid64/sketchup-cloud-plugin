# Minimal SketchUp API fakes shared by every test file (all files load in one
# process). Units: Numeric#mm converts to inches like the real API.
require 'minitest/autorun'
require 'json'

unless defined?(Sketchup)
  module Sketchup
    class Group; end
    class ComponentInstance; end
    class ComponentDefinition; end
    class Color; end
  end
end

class Numeric
  def mm = self / 25.4 unless method_defined?(:mm)
end

module Sketchup
  class << self
    attr_accessor :active_model

    def test_defaults = (@test_defaults ||= {})
    def read_default(section, key, default = nil) = test_defaults.fetch([section, key], default)
    def write_default(section, key, value) = test_defaults[[section, key]] = value
  end
end

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x = x
      @y = y
      @z = z
    end

    def to_a = [x, y, z]
  end

  class Vector3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def %(other) = x * other.x + y * other.y + z * other.z
    def to_a = [x, y, z]
  end

  class Transformation
    attr_reader :value
    def initialize(value = nil) = @value = value
    def self.translation(vector) = new([:translation, vector.to_a])
    def to_a = value
    def identity? = value.nil?
    def ==(other) = other.is_a?(Transformation) && value == other.value
  end
end

module FakeSketchup
  module Attributes
    def attrs = (@attrs ||= {})
    def get_attribute(dict, key, default = nil) = attrs.fetch([dict, key], default)
    def set_attribute(dict, key, value) = attrs[[dict, key]] = value
  end

  class Face
    attr_reader :points, :pushed
    def initialize(points)
      @points = points
      @flipped = false
    end

    def normal
      a, b, c = points.first(3).map(&:to_a)
      u = b.zip(a).map { |p, q| p - q }
      v = c.zip(a).map { |p, q| p - q }
      n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
      n = n.map(&:-@) if @flipped
      Geom::Vector3d.new(*n)
    end

    def reverse! = @flipped = !@flipped
    def pushpull(distance) = @pushed = distance
  end

  class Entities
    include Enumerable
    attr_reader :items, :faces
    def initialize = (@items = []; @faces = [])
    def each(&block) = items.each(&block)
    def add_group = Group.new.tap { |g| items << g }

    def add_instance(definition, transformation)
      instance = Instance.new(definition, transformation)
      definition.instances << instance
      items << instance
      instance
    end

    def add_face(points) = Face.new(points).tap { |f| faces << f }
    def add_circle(centre, normal, radius, segments)
      n = normal.to_a
      u = n[0].abs == 1 ? [0, 1, 0] : [1, 0, 0]
      v = [n[1] * u[2] - n[2] * u[1], n[2] * u[0] - n[0] * u[2], n[0] * u[1] - n[1] * u[0]]
      Array.new(segments) do |i|
        a = 2 * Math::PI * i / segments
        Geom::Point3d.new(*(0..2).map { |k| centre.to_a[k] + radius * (Math.cos(a) * u[k] + Math.sin(a) * v[k]) })
      end
    end

    def clear!
      items.grep(Instance).each { |i| i.definition.instances.delete(i) }
      items.clear
      faces.clear
    end
  end

  class Material
    attr_accessor :color, :alpha
    attr_reader :name
    def initialize(name) = @name = name
    def display_name = name
  end

  class Materials
    include Enumerable
    def initialize = @list = {}
    def each(&block) = @list.values.each(&block)
    def [](name) = @list[name]
    def add(name) = @list[name] = Material.new(name)
  end

  class Definition < Sketchup::ComponentDefinition
    include Attributes
    attr_reader :name, :entities, :instances
    def initialize(name)
      @name = name
      @entities = Entities.new
      @instances = []
      @valid = true
    end

    def valid? = @valid
    def invalidate = @valid = false
  end

  class Definitions
    include Enumerable
    attr_reader :removed
    def initialize = (@list = []; @removed = [])
    def each(&block) = @list.each(&block)
    def add(name) = Definition.new(name).tap { |d| @list << d }

    def remove(definition)
      @removed << definition
      definition.entities.clear!
      @list.delete(definition)
      definition.invalidate
    end
  end

  class Instance < Sketchup::ComponentInstance
    include Attributes
    attr_accessor :name, :material, :transformation
    attr_reader :definition
    def initialize(definition, transformation)
      @definition = definition
      @transformation = transformation
    end
  end

  class Group < Sketchup::Group
    include Attributes
    attr_accessor :name, :material, :transformation
    attr_reader :entities, :make_unique_calls
    def initialize(locked: false)
      @entities = Entities.new
      @transformation = Geom::Transformation.new
      @locked = locked
      @make_unique_calls = 0
    end

    def definition = self
    def locked? = @locked
    def valid? = true
    def make_unique = (@make_unique_calls += 1; self)
  end

  class Selection
    include Enumerable
    def initialize = @items = []
    def each(&block) = @items.each(&block)
    def clear = @items.clear
    def add(item) = @items << item
  end

  class Model
    attr_reader :definitions, :materials, :entities, :selection, :operations
    attr_accessor :active_path
    def initialize
      @definitions = Definitions.new
      @materials = Materials.new
      @entities = Entities.new
      @selection = Selection.new
      @operations = []
    end

    def start_operation(name, transparent) = @operations << [:start, name, transparent]
    def commit_operation = @operations << [:commit]
    def abort_operation = @operations << [:abort]
  end
end

Sketchup::Color.class_eval do
  attr_reader :rgb
  def initialize(*rgb) = @rgb = rgb
end

class Sketchup::Color
  public :initialize
end

module UI; end

require_relative '../../src/drawer_maker_pro/production'
require_relative '../../src/drawer_maker_pro/calculator'
require_relative '../../src/drawer_maker_pro/cabinet_calculator'
require_relative '../../src/drawer_maker_pro/preview'
require_relative '../../src/drawer_maker_pro/builder'
require_relative '../../src/drawer_maker_pro/cabinet_builder'
require_relative '../../src/drawer_maker_pro/motion'
require_relative '../../src/drawer_maker_pro/cutlist'
require_relative '../../src/drawer_maker_pro/dialog'

module TestHelpers
  DMP = SketchupCloud::DrawerMakerPro

  def assert_close(expected, actual, delta = 0.001, msg = nil)
    assert_in_delta expected, actual, delta, msg
  end

  def part(parts, name)
    found = parts.find { |pt| pt.name == name }
    raise "no part #{name.inspect} in #{parts.map(&:name).inspect}" unless found

    found
  end

  def box_of(pt) = [pt.x, pt.y, pt.z, pt.dx, pt.dy, pt.dz].map { |v| v.round(3) }
end
