require 'rack'
require 'active_support/core_ext/string/conversions'


class Gin
  VERSION = '1.0.0'

  class Error < StandardError; end
  class InvalidRouteError < Error; end
  class MissingParamError < Error; end

  require 'gin/app'
  require 'gin/router'
  require 'gin/controller'
end
