require 'logger'

require 'rack'
require 'active_support/core_ext/string/conversions'
require 'active_support/core_ext/object/to_query'


class Gin
  VERSION = '1.0.0'

  class Error < StandardError; end

  class HttpError < Error;
    STATUS = 500
    def status; STATUS; end
  end

  class BadRequestError         < HttpError; STATUS=400; end
  class UnauthorizedError       < HttpError; STATUS=401; end
  class ForbiddenError          < HttpError; STATUS=403; end
  class NotFoundError           < HttpError; STATUS=404; end
  class InternalServerError     < HttpError; STATUS=500; end
  class BadGatewayError         < HttpError; STATUS=502; end
  class ServiceUnavailableError < HttpError; STATUS=503; end
  class GatewayTimeoutError     < HttpError; STATUS=504; end

  HTTP_ERRORS = Hash.new{|h,k| InternalServerError }
  HTTP_ERRORS.merge!(
    BadRequestError::STATUS         => BadRequestError,
    UnauthorizedError::STATUS       => UnauthorizedError,
    ForbiddenError::STATUS          => ForbiddenError,
    NotFoundError::STATUS           => NotFoundError,
    InternalServerError::STATUS     => InternalServerError,
    BadGatewayError::STATUS         => BadGatewayError,
    ServiceUnavailableError::STATUS => ServiceUnavailableError,
    GatewayTimeoutError::STATUS     => GatewayTimeoutError
  )

  require 'gin/core_ext/cgi'
  require 'gin/core_ext/gin_class'

  require 'gin/app'
  require 'gin/router'
  require 'gin/request'
  require 'gin/response'
  require 'gin/callback'
  require 'gin/controller'
end
