require 'logger'

require 'rack'
require 'active_support/core_ext/string/conversions'
require 'active_support/core_ext/object/to_query'


class Gin
  VERSION = '1.0.0'

  class Error < StandardError; end

  require 'gin/core_ext/cgi'
  require 'gin/core_ext/gin_class'

  require 'gin/app'
  require 'gin/router'
  require 'gin/request'
  require 'gin/response'
  require 'gin/stream'
  require 'gin/errorable'
  require 'gin/filterable'
  require 'gin/controller'
end
