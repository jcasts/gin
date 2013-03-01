require 'yaml'

class Gin::Config

  def initialize dir, environment
    @dir = File.join dir, "*.yml"
    @environment = environment
    @meta = class << self; self; end
    @data = {}
    self.load!
  end


  def load!
    Dir[@dir].each do |filepath|
      c = YAML.load_file(filepath)
      c = (c['default'] || {}).merge (c[@environment] || {})

      name = File.basename(filepath, ".yml")
      set name, c
    end
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
