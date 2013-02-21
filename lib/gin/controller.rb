class Gin::Controller
  extend GinClass
  include Gin::Filterable

  class InvalidFilterError < Gin::Error; end

  ##
  # String representing the controller name.
  # Underscores the class name and removes mentions of 'controller'.
  #   MyApp::FooController.controller_name
  #   #=> "my_app/foo"

  def self.controller_name
    @ctrl_name ||= self.to_s.underscore.gsub(/_?controller_?/,'')
  end


  ##
  # Define an error handler for this Controller. Configurable with exceptions
  # or status codes. Omitting the err_types argument acts as a catch-all for
  # non-explicitly handled errors.
  #
  #   error 502, 503, 504 do
  #     # handle unexpected upstream error
  #   end
  #
  #   error do |err|
  #     # catch-all
  #   end
  #
  #   error Timeout::Error do |err|
  #     # something timed out
  #   end

  def self.error *err_types, &block
    return unless block_given?
    err_types << nil if err_types.empty?

    err_types.each do |name|
      self.error_handlers[name] = block
    end
  end


  ##
  # Run after an error has been raised and optionally handled by an
  # error callback. The block will get run on all errors and is given
  # the exception instance as an argument.

  def self.all_errors &block
    return unless block_given?
    self.error_handlers[:all] = block
  end


  ##
  # Hash of error handlers defined by Gin::Controller.error.

  def self.error_handlers
    @err_handlers ||= self.superclass.respond_to?(:error_handlers) ?
                        self.superclass.error_handlers.dup : {}
  end


  class_proxy_reader :controller_name, :err_handlers

  attr_reader :app, :request, :response, :action


  def initialize app, env
    @app         = app
    @request     = Gin::Request.new env
    @response    = Gin::Response.new
    @action      = nil
  end


  def __call_action__ action #:nodoc:
    @action = action

    __with_filters__ @action do
      __send__ @action
    end

    # TODO: assign and return response
    #       allow for streaming

  rescue => err
    handle_error err
  end


  ##
  # Calls the appropriate error handlers for the given error.
  # Re-raises the error if no handler is found.

  def handle_error err
    key = self.error_handlers.keys.find do |key|
            key === err || err.respond_to?(:status) && key === err.status
          end

    raise err unless key || self.error_handlers[:all]

    instance_exec(err, &self.error_handlers[key])  if key
    instance_exec(err, &self.error_handlers[:all]) if self.error_handlers[:all]
  end


  ##
  # Accessor for main application logger.

  def logger
    @app.logger
  end


  ##
  # Get the request params.

  def params
    @request.params
  end


  ##
  # Build a path to the given controller and action, with any expected params.

  def path_to controller, action, params={}
    @app.router.path_to controller, action, params
  end


  ##
  # Returns the full path to an asset

  def asset_path type, name
    
  end
end
