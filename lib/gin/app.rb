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

  def self.mount ctrl, base_path, &block
    router.add ctrl, base_path, &block
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
  # Check if running in development mode.

  def self.development?
    self.environment == "development"
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



  ##
  # Create a new Rack-mountable Gin::App instance, with an optional rack_app.

  def initialize rack_app=nil
    @rack_app = rack_app
  end


  ##
  # Default Rack call method.

  def call env
    ctrl, action, path_params =
      router.resources_for env['HTTP_METHOD'], env['PATH_INFO']

    if ctrl && action
      ctrl.new(self, env).call action

    elsif @rack_app
      @rack_app.call env

    else
      # Call 404 error
    end
  end


  ##
  # Sugar for self.class.router

  def router
    self.class.router
  end
end
