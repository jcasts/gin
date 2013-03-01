require 'yaml'

class Gin::Config

  attr_reader :dir

  def initialize environment, dir=nil
    self.dir = dir
    @environment = environment
    @meta = class << self; self; end
    @data = {}
    self.load!
  end


  def dir= val
    @dir = File.join(val, "*.yml") if val
  end


  def load!
    return unless @dir
    Dir[@dir].each do |filepath|
      c = YAML.load_file(filepath)
      c = (c['default'] || {}).merge (c[@environment] || {})

      name = File.basename(filepath, ".yml")
      set name, c
    end
    self
  end


  def set name, data
    @data[name] = data
    define_method(name){ @data[name] } unless respond_to? name
  end


  def has? name
    @data.has_key?(name) && respond_to?(name)
  end


  private

  def define_method name, &block
    @meta.send :define_method, name, &block
  end
end
