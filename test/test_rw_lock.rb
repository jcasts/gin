require 'test/test_helper'

class RWLockTest < Test::Unit::TestCase

  def setup
    @lock = Gin::RWLock.new
    @value = "setup"
  end


  def test_local_locking
    val = @lock.write_sync do
      @value = "written"
      @lock.read_sync{ @value }
    end

    assert_equal "written", val
  end


  def test_write_timeout
    Thread.new{ @lock.read_sync{ sleep 0.5 } }
    sleep 0.1
    assert_raises(Gin::RWLock::WriteTimeout) do
      @lock.write_sync{ @value = "FOO" }
    end
    assert_equal "setup", @value
  end


  def test_nested_write_locking
    @lock.write_sync do
      @value = "written"
      @lock.write_sync{ @value = "nested" }
    end
    assert_equal "nested", @value
  end


  def test_nested_read_locking
    @lock.read_sync do
      @lock.read_sync{ @value }
    end
  end


  def test_non_blocking_reads
    threads = []
    start = Time.now
    5.times do
      threads << Thread.new{ @lock.read_sync{ sleep 0.1 } }
    end
    threads.each(&:join)

    assert(0.15 > (Time.now - start))
  end


  def test_read_write_nesting
    @lock.read_sync do
      @lock.write_sync{ @value = "written" }
    end
    assert_equal "written", @value
  end
end
