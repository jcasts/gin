class Gin::StrictHash < Hash

  def [] key
    super key.to_s
  end

  def []= key, value
    super key.to_s, value
  end

  def delete key
    super key.to_s
  end

  def has_key? key
    super key.to_s
  end

  alias key? has_key?

  def merge hash
    return super if hash.class == self.class
    new_hash = self.dup
    new_hash.merge!(hash)
    new_hash
  end

  def merge! hash
    return super if hash.class == self.class
    hash.each{|k,v| self[k] = v}
    self
  end
end
