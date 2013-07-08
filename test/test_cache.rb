require 'test/test_helper'

class RWLockTest < Test::Unit::TestCase

  def setup
    @cache = Gin::Cache.new
  end


  def test_write_timeout
    assert_equal 0.05, @cache.write_timeout
    @cache.write_timeout = 0.1
    assert_equal 0.1, @cache.write_timeout
    assert_equal 0.1, @cache.instance_variable_get("@lock").write_timeout
  end


  def test_write_thread_safe
    @cache[:num] = 0
    threads = []
    10.times do
      threads << Thread.new{ @cache[:num] += 1 }
    end
    threads.each(&:join)

    assert_equal 10, @cache[:num]
  end


  def test_has_key
    assert !@cache.has_key?(:num)
    @cache[:num] = 123
    assert @cache.has_key?(:num)
  end


  def test_cache_value
    val = @cache.cache :num, 1234
    assert_equal 1234, val
    assert_equal 1234, @cache[:num]

    val = @cache.cache :num, 5678
    assert_equal 1234, val
    assert_equal 1234, @cache[:num]
  end


  def test_cache_block
    val = @cache.cache(:num){ 1234 }
    assert_equal 1234, val
    assert_equal 1234, @cache[:num]

    val = @cache.cache(:num){ 5678 }
    assert_equal 1234, val
    assert_equal 1234, @cache[:num]
  end
end
