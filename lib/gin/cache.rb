##
# Gin::Cache is a bare-bones in-memory data store.
# It's thread-safe and built for read-bound data.
# Reads are lock-less when no writes are queued.

class Gin::Cache

  def initialize
    @data = {}
    @lock = Gin::RWLock.new
  end


  ##
  # Set the write timeout when waiting for reader thread locks.
  # Defaults to 0.05 sec. See Gin::RWLock for more details.

  def write_timeout= sec
    @lock.write_timeout = sec
  end


  ##
  # Get the write timeout when waiting for reader thread locks.
  # See Gin::RWLock for more details.

  def write_timeout
    @lock.write_timeout
  end


  ##
  # Get a value from the cache with the given key.

  def [] key
    @lock.read_sync{ @data[key] }
  end


  ##
  # Set a value in the cache with the given key and value.

  def []= key, val
    @lock.write_sync{ @data[key] = val }
  end


  ##
  # Check if the current key exists in the cache.

  def has_key? key
    @lock.read_sync{ @data.has_key? key }
  end


  ##
  # Returns a cache value if it exists. Otherwise, locks and assigns the
  # provided value or block result. Blocks get executed with the write lock
  # to prevent redundant operations.

  def cache key, value=nil, &block
    return self[key] if self.has_key?(key)
    @lock.write_sync{ @data[key] = block_given? ? yield() : value }
  end
end
