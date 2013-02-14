class Gin::Response

  attr_accessor :status

  def initialize
    @status = 200
    @header = Rack::Utils::HeaderHash.new
    @body   = []
  end


  def stream str_or_io
    
  end


  def each &block
    
  end
end
