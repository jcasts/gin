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

  class RouterError < Gin::Error; end

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

  def self.error_delegate ctrl
    @error_delegate = ctrl if ctrl
    @error_delegate
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


  class_proxy_reader :error_delegate, :router
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

    validate_all_controllers!
  end


  ##
  # Default Rack call method.

  def call env
    ctrl, action, env['gin.path_query_hash'] =
      router.resources_for env['REQUEST_METHOD'], env['PATH_INFO']

    dispatch env, ctrl, action

  rescue Exception => err
    status = err.respond_to?(:status) ? err.status : 500
    trace  = err.backtrace.join("\n")
    logger.error "#{err.class.name}: #{err.message}\n#{trace}"

    if self.development?
      body = [err.message].concat(err.backtrace).join("<br/>")
      generic_http_response status, err.class.name, body
    else
      error_http_response status
    end
  end


  ##
  # Dispatch the Rack env to the given controller and action.

  def dispatch env, ctrl, action
    raise Gin::NotFoundError, "No controller or action" unless ctrl && action

    ctrl_inst = ctrl.new(self, env)
    ctrl_inst.call_action action

  rescue Gin::NotFoundError => err
    @rack_app ? @rack_app.call(env) : handle_error(err)

  rescue => err
    handle_error(err)
  end


  ##
  # Handle error with error controller if available, otherwise re-raise.

  def handle_error err
    raise err unless error_ctrl

    logger.warn("[Handle Error] %s: %s\n%s" %
      [err.class.name, err.message, Array(err.backtrace).join("\n")])

    # TODO: Make sure we get a Rack response Array from this
    error_ctrl.new(self, env).handle_error(err)
  end


  ##
  # Creates a generic error Rack response from a status code.

  def error_http_response status
    case status
    when 404
      generic_http_response status, "Page Not Found",
        "The page you requested does not exist."

    when (400..499)
      generic_http_response status, "Invalid Request",
        "Your request could not be completed as is. \
Please review it and try again."

    else
      generic_http_response status, "Internal Server Error",
        "There was a problem processing your request. Please try again later."
    end
  end


  ##
  # Creates a generic Rack response Array, mostly used for uncaught errors.

  def generic_http_response status, title, text
    html = GENERIC_HTML % [title, title, text]
    [status, {"Content-Type" => "text/html"}, [html]]
  end


  private

  def validate_all_controllers!
    actions = {}

    router.each_route do |route, ctrl, action|
      (actions[ctrl] ||= []) << action
    end

    actions.each do |ctrl, actions|
      not_mounted   = ctrl.instance_methods(false) - actions
      raise RouterError, "#{ctrl}##{not_mounted[0]} has no route." unless
        not_mounted.empty?

      extra_mounted = actions - ctrl.instance_methods(false)
      raise RouterError, "#{ctrl}##{extra_mounted[0]} is not a method" unless
        extra_mounted.empty?
    end
  end
end
