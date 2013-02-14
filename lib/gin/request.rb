class Gin::Request < Rack::Request

  def initialize env
    super
    self.params.update env['gin.path_query_hash']
  end
end
