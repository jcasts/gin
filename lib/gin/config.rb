require 'yaml'

##
# Environment-specific config files loading mechanism.
#
#   # config_dir/memcache.yml
#   default: &default
#     host: http://memcache.example.com
#     connections: 5
#
#   development: &dev
#     host: localhost:123321
#     connections: 1
#
#   test: *dev
#
#   staging:
#     host: http://stage-memcache.example.com
#
#   production: *default
#
#
#   # config.rb
#   config = Gin::Config.new 'staging', :dir => 'config/dir'
#
#   config['memcache.host']
#   #=> "http://stage-memcache.example.com"
#
#   config['memcache.connections']
#   #=> 5
#
# Config files get loaded on demand. They may also be reloaded on demand
# by setting the :ttl option to expire values. Values are only expired
# for configs with a source file whose mtime value differs from the one
# it had at its previous load time.
#
#   # 5 minute expiration
#   config = Gin::Config.new 'staging', :ttl => 300

class Gin::Config

  attr_accessor :dir, :logger, :ttl, :environment

  ##
  # Create a new config instance for the given environment name.
  # The environment dictates which part of the config files gets exposed.

  def initialize environment, opts={}
    @environment = environment
    @logger      = opts[:logger] || Logger.new($stdout)
    @ttl         = opts[:ttl]    || false
    @dir         = opts[:dir]    || "./config"

    @data       = {}
    @load_times = {}
    @mtimes     = {}

    @lock = Gin::RWLock.new(opts[:write_timeout])
  end


  ##
  # Get or set the write timeout when waiting for reader thread locks.
  # Defaults to 0.05 sec. See Gin::RWLock for more details.

  def write_timeout sec=nil
    @lock.write_timeout = sec if sec
    @lock.write_timeout
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
  # Load the given config name, or filename.
  #   # Loads @dir/my_config.yml
  #   config.load_config 'my_config'
  #   config['my_config']
  #   #=> data from file
  #
  #   # Loads the given file if it exists.
  #   config.load_config 'path/to/my_config.yml'
  #   config['my_config']
  #   #=> data from file

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

    @lock.write_sync do
      @load_times[name] = Time.now

      mtime = File.mtime(filepath)
      return if mtime == @mtimes[name]

      @mtimes[name] = mtime

      c = YAML.load_file(filepath)
      c = (c['default'] || {}).merge(c[@environment] || {})

      @data[name] = c
    end

  rescue Psych::SyntaxError
    @logger.write "[ERROR] Could not parse config `#{filepath}' as YAML"
    return nil
  end


  ##
  # Sets a new config name and value. Configs set in this manner do not
  # qualify for reloading as they don't have a source file.

  def set name, data
    @lock.write_sync{ @data[name] = data }
  end


  ##
  # Get a config value from its name.
  # Setting safe to true will return nil instead of raising errors.
  # Reloads the config if reloading is enabled and value expired.

  def get name, safe=false
    return @lock.read_sync{ @data[name] } if
      current?(name) || safe && !File.file?(filepath_for(name))

    load_config(name) || @lock.read_sync{ @data[name] }
  end


  ##
  # Checks if the given config is outdated.

  def current? name
    @lock.read_sync do
      @ttl == false && @data.has_key?(name) ||
        !@load_times[name] && @data.has_key?(name) ||
        @load_times[name] && Time.now - @load_times[name] <= @ttl
    end
  end


  ##
  # Checks if a config exists in memory or on disk, by its name.
  #   # If foo config isn't loaded, looks for file under @dir/foo.yml
  #   config.has? 'foo'
  #   #=> true

  def has? name
    @lock.read_sync{ @data.has_key?(name) } || File.file?(filepath_for(name))
  end


  ##
  # Non-raising config lookup. The following query the same value:
  #   # Raises an error if the 'user' key is missing.
  #   config.get('remote_shell')['user']['name']
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


  def filepath_for name
    File.join(@dir, "#{name}.yml")
  end
end
