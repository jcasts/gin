class Gin::Response < Rack::Response

  attr_accessor :status
  attr_reader :body

  def body= value
    value = value.body while Rack::Response === value
    @body = String === value ? [value.to_str] : value
  end


  def finish
    body_out = body

    if [100, 101, 204, 205, 304].include?(status.to_i)
      header.delete "Content-Type"
      header.delete "Content-Length"

      if status.to_i > 200
        close
        body_out = []
      end
    end

    update_content_length

    [status.to_i, header, body_out]
  end


  private

  def update_content_length
    if header["Content-Type"] && !header["Content-Length"] && Array === body
      header["Content-Length"] = body.inject(0) do |l, p|
                                   l + Rack::Utils.bytesize(p)
                                 end.to_s
    end
  end
end
