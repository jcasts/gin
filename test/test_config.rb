require 'test/test_helper'
require 'gin/config'

class ConfigTest < Test::Unit::TestCase

  CONFIG_DIR = File.expand_path("../mock_config", __FILE__)

  def setup
    @error_io = StringIO.new
    @config = Gin::Config.new "development",
                :dir => CONFIG_DIR, :logger => @error_io, :ttl => 300
  end


  def test_config_dev
    assert_equal "localhost", @config['memcache.host']
    assert_equal 1, @config['memcache.connections']

    assert_equal "dev.backend.example.com", @config['backend.host']

    assert_nil @config['not_a_config']
  end


  def test_config_unknown_env
    @config = Gin::Config.new "foo", :dir => CONFIG_DIR

    assert_equal "example.com", @config['memcache.host']
    assert_equal 5, @config['memcache.connections']

    assert_equal "backend.example.com", @config['backend.host']

    assert_nil @config['not_a_config']
  end


  def test_set
    assert !@config.has?('foo'), "Config shouldn't have foo available"
    assert_nil @config['foo']

    @config.set 'foo', 1234
    assert_equal 1234, @config['foo']
  end


  def test_load_all
    assert @config.instance_variable_get("@data").empty?
    @config.load!
    assert_equal %w{backend memcache},
                 @config.instance_variable_get("@data").keys
  end


  def test_bracket
    assert_equal "localhost", @config['memcache.host']
    assert_equal 1, @config['memcache.connections']
  end


  def test_invalid_yaml
    assert_raise Psych::SyntaxError do
      YAML.load_file @config.send(:filepath_for, 'invalid')
    end
    assert_nil @config.load_config('invalid')
  end


  def test_get
    assert_equal "localhost", @config.get('memcache')['host']
    @config.set('memcache', 'host' => 'example.com')
    assert_equal "example.com", @config.get('memcache')['host']
  end


  def test_get_non_existant
    assert_raise Gin::MissingConfig do
      @config.get('non_existant')
    end

    assert_nil @config.get('non_existant', true)
  end


  def test_get_reload
    @config['memcache']
    @config.set('memcache', 'host' => 'example.com')
    @config.instance_variable_set("@load_times", 'memcache' => Time.now - (@config.ttl + 1))
    @config.instance_variable_set("@mtimes", 'memcache' => Time.now)
    assert_equal 'localhost', @config.get('memcache')['host']
  end


  def test_get_reload_no_change
    @config['memcache']
    @config.set('memcache', 'host' => 'example.com')
    @config.instance_variable_set("@load_times", 'memcache' => Time.now - (@config.ttl + 1))
    assert_equal 'example.com', @config.get('memcache')['host']

    last_check = @config.instance_variable_get("@load_times")['memcache']
    assert Time.now - last_check <= 1
  end


  def test_current
    assert !@config.current?('memcache')
    assert @config['memcache']
    assert @config.current?('memcache')

    @config.instance_variable_set("@load_times", 'memcache' => Time.now)
    assert @config.current?('memcache')
  end


  def test_current_expired
    @config.instance_variable_set("@load_times", 'memcache' => Time.now - (@config.ttl + 1))
    assert !@config.current?('memcache')
  end


  def test_current_no_ttl
    assert @config['memcache']
    @config.instance_variable_set("@load_times", 'memcache' => Time.now - (@config.ttl + 1))
    assert !@config.current?('memcache')

    @config.ttl = false
    assert @config.current?('memcache')
  end
end
