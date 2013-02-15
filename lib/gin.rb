require 'rack'
require 'active_support/core_ext/string/conversions'


class Gin
  VERSION = '1.0.0'

  class Error < StandardError; end

  require 'gin/core_ext/cgi'

  require 'gin/app'
  require 'gin/router'
  require 'gin/request'
  require 'gin/response'
  require 'gin/callback'
  require 'gin/controller'
end
