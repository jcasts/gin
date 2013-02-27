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

  RACK_KEYS = { #:nodoc:
    :stack       => 'gin.stack'.freeze,
    :path_params => 'gin.path_query_hash'.freeze
  }.freeze

  GENERIC_HTML = <<-HTML.freeze #:nodoc:
<!DOCTYPE html>
<html>
  <head>
    <title>%s</title>
  </head>
  <body><h1>%s</h1><p>%s</p></body>
</html>
  HTML


  CALLERS_TO_IGNORE = [ # :nodoc:
    /\/gin(\/(.*?))?\.rb$/,             # all gin code
    /lib\/tilt.*\.rb$/,                 # all tilt code
    /^\(.*\)$/,                         # generated code
    /rubygems\/custom_require\.rb$/,    # rubygems require hacks
    /active_support/,                   # active_support require hacks
    /bundler(\/runtime)?\.rb/,          # bundler require hacks
    /<internal:/,                       # internal in ruby >= 1.9.2
    /src\/kernel\/bootstrap\/[A-Z]/     # maglev kernel files
  ]


  def self.inherited subclass   #:nodoc:
    caller_line = caller.find{|line| !CALLERS_TO_IGNORE.any?{|m| line =~ m} }
    dir = File.expand_path("..", caller_line.split(/:\d+:in `</).first)
    subclass.root_dir dir
  end


  ##
  # Create a new intance of the app and call it.

  def self.call env
    @instance ||= self.new
    @instance.call env
  end


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
  # Get or set the root directory of the application.
  # Defaults to the app file's directory.

  def self.root_dir dir=nil
    @root_dir = dir if dir
    @root_dir
  end


  ##
  # Get or set the path to the public directory.
  # Defaults to root_dir + "public"

  def self.public_dir dir=nil
    @public_dir = dir if dir
    @public_dir ||= File.join(root_dir, "public")
  end


  ##
  # Get or set the CDN asset host (and path).
  # If block is given, evaluates the block on every read.

  def self.asset_host host=nil, &block
    @asset_host = host  if host
    @asset_host = block if block_given?
    host = @asset_host.respond_to?(:call) ? @asset_host.call : @asset_host
  end


  ##
  # Returns the asset host for a given asset name. This is useful when assigning
  # a block for the asset_host. The asset_name argument is passed to the block.

  def self.asset_host_for asset_name
     @asset_host.respond_to?(:call) ? @asset_host.call(asset_name) : @asset_host
  end


  ##
  # Define a Gin::Controller as a catch-all error rendering controller.
  # This can be a dedicated controller, or a parent controller
  # such as AppController.
  #
  # If this isn't assigned, errors will be rendered as a plain, generic HTML
  # page with a stack trace (when available).

  def self.error_delegate ctrl=nil
    @error_delegate = ctrl if ctrl
    @error_delegate
  end


  ##
  # Router instance that handles mapping Rack-env -> Controller#action.

  def self.router
    @router ||= Gin::Router.new
  end

  ##
  # Lookup or register a mime type in Rack's mime registry.

  def self.mime_type type, value=nil
    return type if type.nil? || type.to_s.include?('/')
    type = ".#{type}" unless type.to_s[0] == ?.
    return Rack::Mime.mime_type(type, nil) unless value
    Rack::Mime::MIME_TYPES[type] = value
  end

  ##
  # Provides all mime types matching type, including deprecated types:
  #   mime_types :html # => ['text/html']
  #   mime_types :js   # => ['application/javascript', 'text/javascript']

  def self.mime_types type
    type = mime_type type
    type =~ /^application\/(xml|javascript)$/ ? [type, "text/#$1"] : [type]
  end


  ##
  # Add middleware internal to the app.

  def self.use middleware, *args, &block
    middleware << [middleware, *args, block]
  end


  ##
  # List of internal app middleware.

  def self.middleware
    @middleware ||= []
  end


  ##
  # Use rack sessions or not. Supports assigning
  # hash for options. Defaults to true.

  def self.sessions opts=nil
    @session = opts unless opts.nil?
    @session = true if @session.nil?
    @session
  end


  ##
  # Get or set the session secret.
  # Defaults to a new random value on boot.

  def self.session_secret val=nil
    @session_secret = val if val
    @session_secret ||= "%064x" % Kernel.rand(2**256-1)
  end


  ##
  # Use rack-protection or not. Supports assigning
  # hash for options. Defaults to true.

  def self.protection opts=nil
    @protection = opts if opts
    @protection = true if @protection.nil?
    @protection
  end


  ##
  # Get or set the current environment name,
  # by default ENV['RACK_ENV'], or "development".

  def self.environment env=nil
    @environment = env if env
    @environment ||= ENV['RACK_ENV'] || "development"
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


  class_proxy_reader :protection, :sessions, :session_secret, :middleware
  class_proxy_reader :error_delegate, :router
  class_proxy_reader :root_dir, :public_dir, :asset_host
  class_proxy_reader :development?, :test?, :staging?, :production?

  # Application logger. Defaults to log to $stdout.
  attr_accessor :logger

  # App to fallback on if Gin::App is used as middleware and no route is found.
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

    @stack = build_app Rack::Builder.new
  end


  ##
  # Default Rack call method.

  def call env
    if env[RACK_KEYS[:stack]]
      env.delete RACK_KEYS[:stack]
      call! env

    else
      env[RACK_KEYS[:stack]] = true
      @stack.call env
    end
  end


  ##
  # Call App instance without internal middleware.

  def call! env
    return Rack::File.new(public_dir).call(env) if static?(env)

    ctrl, action, env[RACK_KEYS[:path_params]] =
      router.resources_for env['REQUEST_METHOD'], env['PATH_INFO']

    dispatch env, ctrl, action

  rescue Exception => err
    status = err.respond_to?(:http_status) ? err.http_status : 500
    trace  = err.backtrace.join("\n")
    logger.error "#{err.class.name}: #{err.message}\n#{trace}"

    if self.development?
      body = [err.message].concat(err.backtrace).join("<br/>")
      generic_http_response status, err.class.name, body
    else
      error_http_response status
    end
  end


  STATIC_PATH_CLEANER = %r{\.+/|/\.+}  #:nodoc:

  ##
  # Check if the request is for a static file.

  def static? env
    path_info = env['PATH_INFO'].gsub STATIC_PATH_CLEANER, ""
    filepath  = File.join(public_dir, path_info)
    File.file?(filepath)
  end


  ##
  # Dispatch the Rack env to the given controller and action.

  def dispatch env, ctrl, action
    raise Gin::NotFound, "No controller or action" unless ctrl && action

    ctrl_inst = ctrl.new(self, env)
    resp = ctrl_inst.call_action action

  rescue Gin::NotFound => err
    @rack_app ? @rack_app.call(env) : handle_error(err)

  rescue => err
    handle_error(err)
  end


  ##
  # Handle error with error controller if available, otherwise re-raise.

  def handle_error err
    raise err unless error_delegate

    logger.warn("[Handle Error] %s: %s\n%s" %
      [err.class.name, err.message, Array(err.backtrace).join("\n")])

    delegate = error_delegate.new(self, env)
    delegate.handle_error(err)
    delegate.response.finish
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


  ##
  # Get the asset host for a given resource. Passes the asset name to the
  # asset_host block if defined.

  def asset_host_for name
    self.class.asset_host_for name
  end


  ##
  # Sugar for self.class.mime_type getter.

  def mime_type type
    self.class.mime_type type
  end


  private

  def build_app builder
    setup_sessions   builder
    setup_protection builder
    middleware.each do |args|
      block = args.pop if Proc === args.last
      builder.use(*args, &block)
    end

    builder.run self
    builder.to_app
  end


  def setup_sessions builder
    return unless sessions
    options = {}
    options[:secret] = session_secret if session_secret
    options.merge! sessions.to_hash if sessions.respond_to? :to_hash
    builder.use Rack::Session::Cookie, options
  end


  def setup_protection builder
    return unless protection
    options = Hash === protection ? protection.dup : {}
    options[:except] = Array options[:except]
    options[:except] += [:session_hijacking, :remote_token] unless sessions
    options[:reaction] ||= :drop_session
    builder.use Rack::Protection, options
  end


  ##
  # Make sure all controller actions have a route, or raise a RouterError.

  def validate_all_controllers!
    actions = {}

    router.each_route do |route, ctrl, action|
      (actions[ctrl] ||= []) << action
    end

    actions.each do |ctrl, actions|
      not_mounted   = ctrl.actions - actions
      raise RouterError, "#{ctrl}##{not_mounted[0]} has no route." unless
        not_mounted.empty?

      extra_mounted = actions - ctrl.actions
      raise RouterError, "#{ctrl}##{extra_mounted[0]} is not a method" unless
        extra_mounted.empty?
    end
  end
end
