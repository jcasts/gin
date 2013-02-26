class Gin::Request < Rack::Request

  def initialize env
    super
    self.params.update env[Gin::App::RACK_KEYS[:path_params]] if
      env[Gin::App::RACK_KEYS[:path_params]]
  end


  def secure?
    scheme == 'https'
  end


  def forwarded?
    @env.include? "HTTP_X_FORWARDED_HOST"
  end


  def params
    unless @params
      super
      @params = indifferent_params @params
    end

    @params
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
