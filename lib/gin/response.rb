class Gin::Response

  attr_accessor :body, :status
  attr_reader :headers

  def initialize
    @status  = 200
    @headers = Rack::Utils::HeaderHash.new
    @body    = []
  end


  def [] key
    @headers[key]
  end


  def []= key, val
    @headers[key] = val
  end


  def finish
    [@status, @header, @body]
  end
end
