class Gin::Controller
  extend GinClass
  include Gin::Filterable
  include Gin::Errorable

  ##
  # String representing the controller name.
  # Underscores the class name and removes mentions of 'controller'.
  #   MyApp::FooController.controller_name
  #   #=> "my_app/foo"

  def self.controller_name
    @ctrl_name ||= self.to_s.underscore.gsub(/_?controller_?/,'')
  end


  class_proxy_reader :controller_name

  attr_reader :app, :request, :response, :action


  def initialize app, env
    @app         = app
    @request     = Gin::Request.new env
    @response    = Gin::Response.new
    @action      = nil
  end


  def __call_action__ action #:nodoc:
    @action = action

    with_filters_for @action do
      __send__ @action
    end

    # TODO: assign and return response
    #       allow for streaming

  rescue => err
    handle_error err
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
