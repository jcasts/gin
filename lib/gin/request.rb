class Gin::Request < Rack::Request

  def initialize env
    super
    self.params.update env['gin.path_query_hash']
  end


  def params
    super
    @params = indifferent_params @params
  end


  private

  ##
  # Enable string or symbol key access to the nested params hash.

  def indifferent_params(object)
    case object
    when Hash
      new_hash = indifferent_hash
      object.each { |key, value| new_hash[key] = indifferent_params(value) }
      new_hash
    when Array
      object.map { |item| indifferent_params(item) }
    else
      object
    end
  end


  ##
  # Creates a Hash with indifferent access.

  def indifferent_hash
    Hash.new {|hash,key| hash[key.to_s] if Symbol === key }
  end
end
