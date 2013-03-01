require 'test/test_helper'
require 'gin/config'

class ConfigTest < Test::Unit::TestCase

  def config_dir
    File.expand_path("../mock_config", __FILE__)
  end


  def test_config_dev
    config = Gin::Config.new config_dir, "development"

    assert_equal "localhost", config.memcache['host']
    assert_equal 1, config.memcache['connections']

    assert_equal "dev.backend.example.com", config.backend['host']

    assert_raises(NoMethodError){ config.not_a_config }
  end


  def test_config_unknown_env
    config = Gin::Config.new config_dir, "foo"

    assert_equal "example.com", config.memcache['host']
    assert_equal 5, config.memcache['connections']

    assert_equal "backend.example.com", config.backend['host']

    assert_raises(NoMethodError){ config.not_a_config }
  end
end
