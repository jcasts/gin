require 'test/test_helper'
require 'gin/config'

class ConfigTest < Test::Unit::TestCase

  CONFIG_DIR = File.expand_path("../mock_config", __FILE__)

  def setup
    @error_io = StringIO.new
    @config = Gin::Config.new "development", dir: CONFIG_DIR, logger: @error_io
  end


  def test_config_dev
    assert_equal "localhost", @config.memcache['host']
    assert_equal 1, @config.memcache['connections']

    assert_equal "dev.backend.example.com", @config.backend['host']

    assert_raises(Gin::MissingConfig){ @config.not_a_config }
  end


  def test_config_unknown_env
    @config = Gin::Config.new "foo", dir: CONFIG_DIR

    assert_equal "example.com", @config.memcache['host']
    assert_equal 5, @config.memcache['connections']

    assert_equal "backend.example.com", @config.backend['host']

    assert_raises(Gin::MissingConfig){ @config.not_a_config }
  end


  def test_set
    assert !@config.respond_to?(:foo), "Config shouldn't respond to #foo"
    assert !@config.has?('foo'), "Config shouldn't have foo available"
    assert_nil @config['foo']

    @config.set 'foo', 1234

    assert_equal 1234, @config.foo
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
    assert_nil @config.send(:load_config, 'invalid')
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
    assert_equal 'localhost', @config.get('memcache')['host']
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
