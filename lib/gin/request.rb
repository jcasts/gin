class Gin::Request < Rack::Request
  include Gin::Constants

  def initialize env
    super
    self.params.update env[GIN_PATH_PARAMS] if env[GIN_PATH_PARAMS]
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
    @params ||= process_params(super) || {}
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

  M_BOOLEAN = /^true|false$/           #:nodoc:
  M_FLOAT   = /^-?([1-9]\d+|\d)\.\d+$/ #:nodoc:
  M_INTEGER = /^-?([1-9]\d+|\d)$/      #:nodoc:

  ##
  # Enable string or symbol key access to the nested params hash.
  # Make String numbers into Numerics.

  def process_params object
    case object
    when Hash
      new_hash = Gin::StrictHash.new
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
end
