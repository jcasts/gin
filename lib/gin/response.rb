class Gin::Response < Rack::Response

  NO_BODY_STATUSES = [100, 101, 204, 205, 304].freeze #:nodoc:
  H_CTYPE   = "Content-Type".freeze   #:nodoc:
  H_CLENGTH = "Content-Length".freeze #:nodoc:

  attr_accessor :status
  attr_reader :body

  def body= value
    value = value.body while Rack::Response === value
    @body = String === value ? [value] : value
    @body
  end


  def finish
    body_out = body

    if NO_BODY_STATUSES.include?(status.to_i)
      header.delete H_CTYPE
      header.delete H_CLENGTH

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
    if header[H_CTYPE] && !header[H_CLENGTH] && Array === body
      header[H_CLENGTH] = body.inject(0) do |l, p|
                            l + Rack::Utils.bytesize(p)
                          end.to_s
    end
  end
end
