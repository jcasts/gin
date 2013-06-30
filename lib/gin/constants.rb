module Gin::Constants
  EPOCH = Time.at(0)

  # Rack env constants
  FWD_FOR        = 'HTTP_X_FORWARDED_FOR'.freeze
  FWD_HOST       = 'HTTP_X_FORWARDED_HOST'.freeze
  REMOTE_ADDR    = 'REMOTE_ADDR'.freeze
  REMOTE_USER    = 'REMOTE_USER'.freeze
  HTTP_VERSION   = 'HTTP_VERSION'.freeze
  REQ_METHOD     = 'REQUEST_METHOD'.freeze
  PATH_INFO      = 'PATH_INFO'.freeze
  QUERY_STRING   = 'QUERY_STRING'.freeze
  IF_MATCH       = 'HTTP_IF_MATCH'.freeze
  IF_NONE_MATCH  = 'HTTP_IF_NONE_MATCH'.freeze
  IF_MOD_SINCE   = 'HTTP_IF_MODIFIED_SINCE'.freeze
  IF_UNMOD_SINCE = 'HTTP_IF_UNMODIFIED_SINCE'.freeze

  ASYNC_CALLBACK = 'async.callback'.freeze

  # Rack response header constants
  ETAG            = 'ETag'.freeze
  CNT_LENGTH      = 'Content-Length'.freeze
  CNT_TYPE        = 'Content-Type'.freeze
  CNT_DISPOSITION = 'Content-Disposition'.freeze
  LOCATION        = 'Location'.freeze
  LAST_MOD        = 'Last-Modified'.freeze
  CACHE_CTRL      = 'Cache-Control'.freeze
  EXPIRES         = 'Expires'.freeze
  PRAGMA          = 'Pragma'.freeze

  # Gin env constants
  GIN_STACK       = 'gin.stack'.freeze
  GIN_ROUTE       = 'gin.http_route'.freeze
  GIN_PATH_PARAMS = 'gin.path_query_hash'.freeze
  GIN_CTRL        = 'gin.controller'.freeze
  GIN_ACTION      = 'gin.action'.freeze
  GIN_STATIC      = 'gin.static'.freeze
  GIN_RELOADED    = 'gin.reloaded'.freeze
  GIN_ERRORS      = 'gin.errors'.freeze
  GIN_TIMESTAMP   = 'gin.timestamp'.freeze

  # Environment names
  ENV_DEV   = "development".freeze
  ENV_TEST  = "test".freeze
  ENV_STAGE = "staging".freeze
  ENV_PROD  = "production".freeze

  # Other
  SESSION_SECRET = "%064x" % Kernel.rand(2**256-1)
end
