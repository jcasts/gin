require 'yaml'

class Gin::Config

  attr_accessor :dir, :logger, :ttl

  def initialize environment, opts={}
    @environment = environment
    @logger      = opts[:logger] || $stdout
    @ttl         = opts[:ttl]    || 300
    @dir         = opts[:dir]    || "./config"

    @meta = class << self; self; end
    @data = {}
    @load_times = {}
  end


  ##
  # Force-load all the config files in the config directory.

  def load!
    return unless @dir
    Dir[File.join(@dir, "*.yml")].each do |filepath|
      load_config filepath
    end
    self
  end


  ##
  # Sets a new config name and value.

  def set name, data
    @data[name] = data
    define_method(name){ get(name) } unless respond_to? name
    @data[name]
  end


  ##
  # Get a config value from its name.
  # Setting safe to true will return nil instead of raising errors.
  # Reloads the config if reloading is enabled and value expired.

  def get name, safe=false
    return @data[name] if current?(name) ||
                          safe && !File.file?(filepath_for(name))
    load_config(name) || @data[name]
  end


  ##
  # Checks if the given config is outdated.

  def current? name
    @ttl == false || @data.has_key?(name) && @load_times[name].nil? ||
      @load_times[name] && Time.now - @load_times[name] <= @ttl
  end


  ##
  # Checks if a config exists in memory or on disk, by its name.
  #   # If foo config isn't loaded, looks for file under @dir/foo.yml
  #   config.has? 'foo'
  #   #=> true

  def has? name
    @data.has_key?(name) && respond_to?(name) || File.file?(filepath_for(name))
  end


  ##
  # Non-raising config lookup. The following query the same value:
  #   # Raises an error if the 'user' key is missing.
  #   config.remote_shell['user']['name']
  #
  #   # Doesn't raise an error if a key is missing.
  #   # Doesn't support configs with '.' in the key names.
  #   config['remote_shell.user.name']

  def [] key
    chain = key.to_s.split(".")
    name = chain.shift
    curr = get(name, true)
    return unless curr

    chain.each do |k|
      return unless Array === curr || Hash === curr
      val = curr[k]
      val = curr[k.to_i] if val.nil? && k.to_i.to_s == k
      curr = val
    end

    curr
  end


  private

  def load_config name
    name = name.to_s

    if File.file?(name)
      filepath = name
      name = File.basename(filepath, ".yml")
    else
      filepath = filepath_for(name)
    end

    raise Gin::MissingConfig, "No config file at #{filepath}" unless
      File.file?(filepath)

    @load_times[name] = Time.now

    c = YAML.load_file(filepath)
    c = (c['default'] || {}).merge(c[@environment] || {})

    set name, c

  rescue Psych::SyntaxError
    @logger.write "[ERROR] Could not parse config `#{filepath}' as YAML"
    return nil
  end


  def filepath_for name
    File.join(@dir, "#{name}.yml")
  end


  def method_missing name, *args, &block
    super if !args.empty? && !block_given?
    load_config(name) || super
  end


  def define_method name, &block
    @meta.send :define_method, name, &block
  end
end
