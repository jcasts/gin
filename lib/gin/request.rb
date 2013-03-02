class Gin::Request < Rack::Request

  def initialize env
    super
    self.params.update env[Gin::App::RACK_KEYS[:path_params]] if
      env[Gin::App::RACK_KEYS[:path_params]]
  end


  def forwarded?
    @env.include? "HTTP_X_FORWARDED_HOST"
  end


  def ssl?
    scheme == 'https'
  end


  def safe?
    get? or head? or options? or trace?
  end


  def idempotent?
    safe? or put? or delete?
  end


  def params
    unless @params
      super
      @params = process_params @params
    end

    @params
  end


  private

  M_BOOLEAN = /^true|false$/  #:nodoc:
  M_FLOAT   = /^\d+\.\d+$/    #:nodoc:
  M_INTEGER = /^\d+$/         #:nodoc:

  ##
  # Enable string or symbol key access to the nested params hash.
  # Make String numbers into Numerics.

  def process_params object
    case object
    when Hash
      new_hash = indifferent_hash
      object.each { |key, value| new_hash[key] = process_params(value) }
      new_hash
    when Array
      object.map { |item| process_params(item) }
    when M_BOOLEAN
      object == "true"
    when M_FLOAT
      object.to_f
    when M_INTEGER
      object.to_i
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
