class Gin::Response

  attr_accessor :status
  attr_reader :body, :header

  def initialize
    @status = 200
    @header = Rack::Utils::HeaderHash.new
    @body   = []
  end


  def stream use_ev=false
    
  end


  def to_a
    [@status, @header, @body]
  end
end
