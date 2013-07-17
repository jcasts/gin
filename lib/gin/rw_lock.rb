##
# Read-Write lock pair for accessing data that is mostly read-bound.
# Reading is done without locking until a write operation is started.
#
#   lock = Gin::RWLock.new
#   lock.write_sync{ write_to_the_object }
#   value = lock.read_sync{ read_from_the_object }
#
# The RWLock is built to work primarily in Thread-pool type environments and its
# effectiveness is much less for Thread-spawn models.
#
# RWLock also shows increased performance in GIL-less Ruby implementations such
# as Rubinius 2.x.
#
# Using write_sync from inside a read_sync block is safe, but the inverse isn't:
#
#   lock = Gin::RWLock.new
#
#   # This is OK.
#   lock.read_sync do
#     get_value || lock.write_sync{ update_value }
#   end
#
#   # This is NOT OK and will raise a ThreadError.
#   # It's also not necessary because read sync-ing is inferred
#   # during write syncs.
#   lock.write_sync do
#     update_value
#     lock.read_sync{ get_value }
#   end

class Gin::RWLock

  class WriteTimeout < StandardError; end

  TIMEOUT_MSG = "Took too long to lock all config mutexes. \
Try increasing the value of write_timeout."

  # The amount of time to wait for writer threads to get all the read locks.
  attr_accessor :write_timeout


  def initialize write_timeout=nil
    @wmutex        = Mutex.new
    @write_timeout = write_timeout || 0.05
    @mutex_id      = :"rwlock_#{self.object_id}"
    @mutex_owned_id = :"#{@mutex_id}_owned"
    @rmutex_owned_id = :"#{@mutex_id}_r_owned"
  end


  def write_sync
    lock_mutexes = []
    was_locked   = Thread.current[@mutex_owned_id]

    write_mutex.lock unless was_locked
    Thread.current[@mutex_owned_id] = true

    start = Time.now

    Thread.list.each do |t|
      mutex = t[@mutex_id]
      next if !mutex || t == Thread.current
      until mutex.try_lock
        Thread.pass
        raise WriteTimeout, TIMEOUT_MSG if Time.now - start > @write_timeout
      end
      lock_mutexes << mutex
    end

    yield
  ensure
    lock_mutexes.each(&:unlock)
    unless was_locked
      Thread.current[@mutex_owned_id] = false
      write_mutex.unlock
    end
  end


  def read_sync
    was_locked = Thread.current[@rmutex_owned_id]
    unless was_locked
      read_mutex.lock
      Thread.current[@rmutex_owned_id] = true
    end
    yield
  ensure
    if !was_locked
      Thread.current[@rmutex_owned_id] = false
      read_mutex.unlock
    end
  end


  private


  def write_mutex
    @wmutex
  end


  def read_mutex
    return Thread.current[@mutex_id] if Thread.current[@mutex_id]
    if Thread.current[@mutex_owned_id]
      Thread.current[@mutex_id] = Mutex.new
    else
      @wmutex.synchronize{ Thread.current[@mutex_id] = Mutex.new }
    end
  end
end
