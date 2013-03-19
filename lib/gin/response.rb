class Gin::Response < Rack::Response
  include Gin::Constants

  NO_HEADER_STATUSES = [100, 101, 204, 205, 304].freeze #:nodoc:

  attr_accessor :status
  attr_reader :body

  def body= value
    value = value.body while Rack::Response === value
    @body = value.respond_to?(:each) ? value : [value.to_s]
    @body
  end


  def finish
    body_out = body
    header[CNT_TYPE] ||= 'text/html;charset=UTF-8'

    if NO_HEADER_STATUSES.include?(status.to_i)
      header.delete CNT_TYPE
      header.delete CNT_LENGTH

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
    if header[CNT_TYPE] && !header[CNT_LENGTH]
      case body
      when Array
        header[CNT_LENGTH] = body.inject(0) do |l, p|
                               l + Rack::Utils.bytesize(p)
                             end.to_s
      when File
        header[CNT_LENGTH] = body.size.to_s
      end
    end
  end
end
