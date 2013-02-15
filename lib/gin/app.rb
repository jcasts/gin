##
# The Gin::App is the entry point for Rack, for all Gin Applications.
# This class MUST be subclassed and initialized.
#   # my_app.rb
#   class MyApp < Gin::App
#     require 'my_controller'
#     mount MyController, "/"
#   end
#
#   # config.ru
#   require 'my_app'
#   run MyApp.new

class Gin::App
  extend GinClass

  GENERIC_HTML = <<-HTML
<!DOCTYPE html>
<html>
  <head>
    <title>%s</title>
  </head>
  <body><h1>%s</h1><p>%s</p></body>
</html>
  HTML


  ##
  # Mount a Gin::Controller into the App and specify a base path. If controller
  # mounts at root, use "/" as the base path.
  #   mount UserController, "/user" do
  #     get  :index,  "/"
  #     get  :show,   "/:id"
  #     post :create, "/"
  #     get  :stats        # mounts to "/stats" by default
  #     any  :logged_in    # any HTTP verb will trigger this action
  #   end
  #
  # Controllers with non-mounted actions will throw a warning at boot time.

  def self.mount ctrl, base_path=nil, &block
    router.add ctrl, base_path, &block
  end


  ##
  # Define a Gin::Controller as a catch-all error rendering controller.
  # This can be a dedicated controller, or a parent controller
  # such as AppController.
  #
  # If this isn't assigned, errors will be rendered as a plain, generic HTML
  # page with a stack trace (when available).

  def self.errors ctrl
    @error_ctrl = ctrl
  end


  ##
  # Accessor for the default error handling Gin::Controller.

  def self.error_ctrl
    @error_ctrl
  end


  ##
  # Router instance that handles mapping Rack-env -> Controller#action.

  def self.router
    @router ||= Gin::Router.new
  end


  ##
  # Access to the current environment name,
  # by default ENV['RACK_ENV'], or "development".

  def self.environment
    @environment ||= ENV['RACK_ENV'] || "development"
  end


  ##
  # Environment name setter

  def self.environment= val
    @environment = val
  end



  ##
  # Check if running in development mode.

  def self.development?
    self.environment == "development"
  end


  ##
  # Check if running in test mode.

  def self.test?
    self.environment == "test"
  end


  ##
  # Check if running in staging mode.

  def self.staging?
    self.environment == "staging"
  end


  ##
  # Check if running in production mode.

  def self.production?
    self.environment == "production"
  end


  class_proxy_reader :error_ctrl, :router
  class_proxy_reader :development?, :test?, :staging?, :production?

  attr_accessor :logger
  attr_reader :rack_app


  ##
  # Create a new Rack-mountable Gin::App instance, with an optional
  # rack_app and logger.

  def initialize rack_app=nil, logger=nil
    if !rack_app.respond_to?(:call) && rack_app.respond_to?(:log) && logger.nil?
      @rack_app = nil
      @logger   = rack_app
    else
      @rack_app = rack_app
      @logger   = Logger.new $stdout
    end
  end


  ##
  # Default Rack call method.

  def call env
    ctrl, action, env['gin.path_query_hash'] =
      router.resources_for env['REQUEST_METHOD'], env['PATH_INFO']

    if ctrl && action
      dispatch env, ctrl, action

    elsif @rack_app
      @rack_app.call env

    elsif error_ctrl && error_ctrl.handles?(404)
      error_ctrl.trigger(404, error_ctrl.new(self, request))

    else
      generic_http_response 404, "Page Not Found",
        "Sorry, the page you are looking for does not exist."
    end

  rescue Exception => err
    title = "#{err.class.name}: #{err.message}"
    trace = err.backtrace.join("\n")

    logger.error [title, trace].join("\n")

    if self.development?
      generic_http_response 500, title, trace
    else
      generic_http_response 500, "Internal Server Error",
        "There was a problem processing your request. Please try again later."
    end
  end


  ##
  # Dispatch the Rack env to the given controller and action.

  def dispatch env, ctrl, action
    ctrl_inst = ctrl.new(self, env)
    ctrl_inst.__call__ action

  rescue => err
    raise err unless error_ctrl &&
      (error_ctrl.handles?(e.class) || error_ctrl === ctrl_inst)

    logger.warn("[Caught Error] %s: %s\n%s" %
      [err.class.name, err.message, Array(err.backtrace).join("\n")])

    error_ctrl.trigger(e.class, error_ctrl.new(self, env))
  end


  ##
  # Creates a generic Rack response Array, mostly used for uncaught errors.

  def generic_http_response status, title, text
    html = GENERIC_HTML % [title, title, text]
    [status, {"Content-Type" => "text/html"}, [html]]
  end
end
