class Gin::Request < Rack::Request
  include Gin::Constants

  attr_accessor :autocast_params  # :nodoc:

  def initialize env
    @params = nil
    @params_processed = false
    @autocast_params = true
    super
  end


  def forwarded?
    @env.include? FWD_HOST
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
    return @params if @params_processed
    @params = super
    @params.update @env[GIN_PATH_PARAMS] if @env[GIN_PATH_PARAMS]
    @params = process_params(@params)
    @params_processed = true
    @params
  end


  def ip
    if addr = @env['HTTP_X_FORWARDED_FOR']
      (addr.split(',').grep(/\d\./).first || @env['REMOTE_ADDR']).to_s.strip
    else
      @env['REMOTE_ADDR']
    end
  end

  alias remote_ip ip


  private

  M_BOOLEAN = /^(true|false)$/         #:nodoc:
  M_FLOAT   = /^-?([1-9]\d+|\d)\.\d+$/ #:nodoc:
  M_INTEGER = /^-?([1-9]\d+|\d)$/      #:nodoc:

  ##
  # Enable string or symbol key access to the nested params hash.
  # Make String numbers into Numerics.

  def process_params object
    return object unless @autocast_params

    case object
    when Hash
      new_hash = Gin::StrictHash.new
      object.each do |key, value|
        new_hash[key] = process_param?(key) ? process_params(value) : value
      end
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


  def process_param? name
    if Hash === @autocast_params
      return false if @autocast_params[:except] &&
                      @autocast_params[:except].include?(name.to_sym)

      return @autocast_params[:only].include?(name.to_sym) if
        @autocast_params[:only]
    end

    !!@autocast_params
  end
end
