require 'test/test_helper'

class CacheTest < Test::Unit::TestCase

  def setup
    @cache = Gin::Cache.new
  end


  def test_write_timeout
    assert_equal 0.05, @cache.write_timeout
    @cache.write_timeout = 0.1
    assert_equal 0.1, @cache.write_timeout
    assert_equal 0.1, @cache.instance_variable_get("@lock").write_timeout
  end


  # This test only valid for non-GC Ruby implementations
  def test_readwrite_thread_safe
    @cache[:num] = 0
    @num = 0

    threads = []
    15.times do
      threads << Thread.new{ @cache[:num] = Thread.current.object_id }
    end
    15.times do
      threads << Thread.new{ assert @cache[:num] }
    end
    threads.each do |t|
      t.join
    end
  end


  def test_increase
    assert_equal 1, @cache.increase(:num)
    assert_equal 1, @cache[:num]

    @cache.increase(:num, 0.2)
    assert_equal 1.2, @cache[:num]
  end


  def test_increase_invalid
    @cache[:num] = "foo"
    assert_nil @cache.increase(:num)
    assert_equal "foo", @cache[:num]
  end


  def test_decrease
    @cache.decrease(:num)
    assert_equal -1, @cache[:num]

    @cache.decrease(:num, 0.2)
    assert_equal -1.2, @cache[:num]
  end


  def test_decrease_invalid
    @cache[:num] = "foo"
    assert_nil @cache.decrease(:num)
    assert_equal "foo", @cache[:num]
  end


  def test_increase_thread_safe
    threads = []
    15.times do
      threads << Thread.new{ @cache.increase(:num) }
    end
    threads.each do |t|
      t.join
    end

    assert_equal 15, @cache[:num]
  end


  def test_decrease_thread_safe
    threads = []
    15.times do
      threads << Thread.new{ @cache.decrease(:num) }
    end
    threads.each do |t|
      t.join
    end

    assert_equal -15, @cache[:num]
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
