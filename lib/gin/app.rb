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
  include Gin::Constants

  class RouterError < Gin::Error; end

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
    filepath = File.expand_path(caller_line.split(/:\d+:in `/).first)
    dir      = File.dirname(filepath)
    subclass.root_dir dir
    subclass.instance_variable_set("@source_file", filepath)
    subclass.instance_variable_set("@source_class", subclass.to_s)
  end


  ##
  # Create a new intance of the app and call it.

  def self.call env
    @instance ||= self.new
    @instance.call env
  end


  ##
  # Enable or disable auto-app reloading.
  # On by default in development mode.
  #
  # In order for an app to be reloadable, the libs and controllers must be
  # required from the Gin::App class context, or use MyApp.require("lib").
  #
  # Reloading is not supported for applications defined in the config.ru file.

  def self.autoreload val=nil
    @autoreload = val unless val.nil?

    if @autoreload.nil?
      @autoreload = File.extname(source_file) != ".ru" && development?
    end

    if @autoreload && (!defined?(Gin::Reloadable) || !include?(Gin::Reloadable))
      Object.send :require, 'gin/reloadable'
      include Gin::Reloadable
    end

    @autoreload
  end


  ##
  # Custom require used for auto-reloading.

  def self.require file
    if autoreload
      track_require file
    else
      super file
    end
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
  #
  # Restful routes are automatically mounted when no block is given:
  #
  #   mount UserController
  #   # restfully mounted to /user
  #   # non-canonical actions are mounted to /user/<action_name>
  #
  # Mount blocks also support routing whatever actions are left to their restful
  # defaults:
  #
  #   mount UserController do
  #     get :foo, "/"
  #     defaults
  #   end
  #
  # All Gin::Controller methods are considered actions and will be mounted in
  # restful mode. For helper methods, include a module into your controller.

  def self.mount ctrl, base_path=nil, &block
    router.add ctrl, base_path, &block
  end


  ##
  # Returns the source file of the current app.

  def self.source_file
    @source_file
  end


  def self.namespace #:nodoc:
    # Parent namespace of the App class. Used for reloading purposes.
    Gin.const_find(@source_class.split("::")[0..-2]) if @source_class
  end


  def self.source_class #:nodoc:
    # Lookup the class from its name. Used for reloading purposes.
    Gin.const_find(@source_class) if @source_class
  end


  ##
  # Get or set the root directory of the application.
  # Defaults to the app file's directory.

  def self.root_dir dir=nil
    @root_dir = dir if dir
    @root_dir
  end


  ##
  # Get or set the path to the config directory.
  # Defaults to root_dir + "config"
  #
  # Configs are expected to be YAML files following this pattern:
  #   default: &default
  #     key: value
  #
  #   development: *default
  #     other_key: value
  #
  #   production: *default
  #     ...
  #
  # Configs will be named according to the filename, and only the config for
  # the current environment will be accessible.

  def self.config_dir dir=nil
    @config_dir = dir if dir
    @config_dir ||= File.join(root_dir, "config")
  end


  ##
  # Access the config for your application, loaded from the config_dir.
  #   # config/memcache.yml
  #   default: &default
  #     host: example.com
  #     connections: 1
  #   development: *default
  #     host: localhost
  #
  #   # access from App class or instance
  #   config.memcache['host']

  def self.config
    @config ||= Gin::Config.new environment, config_dir
  end


  ##
  # Loads all configs from the config_dir.

  def self.load_config
    return unless File.directory?(config_dir)
    config.dir = config_dir
    config.load!
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
  # Returns the first 8 bytes of the asset file's md5.
  # File path is assumed relative to the public_dir.

  def self.asset_version path
    path = File.expand_path(File.join(public_dir, path))
    return unless File.file?(path)

    @asset_versions       ||= {}
    @asset_versions[path] ||= md5(path)
  end


  MD5 = RUBY_PLATFORM =~ /darwin/ ? 'md5 -q' : 'md5sum' #:nodoc:

  def self.md5 path #:nodoc:
    `#{MD5} #{path}`[0...8]
  end


  ##
  # Define a Gin::Controller as a catch-all error rendering controller.
  # This can be a dedicated controller, or a parent controller
  # such as AppController. Defaults to Gin::Controller.
  #
  # The error delegate should handle the following errors
  # for creating custom pages for Gin errors:
  #   Gin::NotFound, Gin::BadRequest, ::Exception

  def self.error_delegate ctrl=nil
    @error_delegate = ctrl if ctrl
    @error_delegate ||= Gin::Controller
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
  # Add middleware internally to the app.
  # Middleware statuses and Exceptions will NOT be
  # handled by the error_delegate.

  def self.use middleware, *args, &block
    ary = [middleware, *args]
    ary << block if block_given?
    self.middleware << ary
  end


  ##
  # List of internal app middleware.

  def self.middleware
    @middleware ||= []
  end


  ##
  # Use rack sessions or not. Supports assigning
  # hash for options. Defaults to false.

  def self.sessions opts=nil
    @session = opts unless opts.nil?
    @session = false if @session.nil?
    @session
  end


  ##
  # Get or set the session secret String.
  # Defaults to a new random value on boot.

  def self.session_secret val=nil
    @session_secret = val if val
    @session_secret ||= "%064x" % Kernel.rand(2**256-1)
  end


  ##
  # Use rack-protection or not. Supports assigning
  # hash for options. Defaults to false.

  def self.protection opts=nil
    @protection = opts unless opts.nil?
    @protection = false if @protection.nil?
    @protection
  end


  ##
  # Get or set the current environment name,
  # by default ENV ['RACK_ENV'], or "development".

  def self.environment env=nil
    @environment = env if env
    @environment ||= ENV['RACK_ENV'] || ENV_DEV
  end


  ##
  # Check if running in development mode.

  def self.development?
    self.environment == ENV_DEV
  end


  ##
  # Check if running in test mode.

  def self.test?
    self.environment == ENV_TEST
  end


  ##
  # Check if running in staging mode.

  def self.staging?
    self.environment == ENV_STAGE
  end


  ##
  # Check if running in production mode.

  def self.production?
    self.environment == ENV_PROD
  end


  class_proxy :protection, :sessions, :session_secret, :middleware, :autoreload
  class_proxy :error_delegate, :router
  class_proxy :root_dir, :public_dir
  class_proxy :mime_type, :asset_host_for, :asset_host, :asset_version
  class_proxy :environment, :development?, :test?, :staging?, :production?
  class_proxy :load_config, :config, :config_dir

  # Application logger. Defaults to log to $stdout.
  attr_accessor :logger

  # App to fallback on if Gin::App is used as middleware and no route is found.
  attr_reader :rack_app

  # Internal Rack stack.
  attr_reader :stack


  ##
  # Create a new Rack-mountable Gin::App instance, with an optional
  # rack_app and logger.

  def initialize rack_app=nil, logger=nil
    load_config

    if !rack_app.respond_to?(:call) && rack_app.respond_to?(:<<) && logger.nil?
      @rack_app = nil
      @logger   = rack_app
    else
      @rack_app = rack_app
      @logger   = $stdout
    end

    validate_all_controllers!

    @app   = self
    @stack = build_app Rack::Builder.new
  end


  ##
  # Used for auto reloading the whole app in development mode.
  # Will only reload if Gin::App.autoreload is set to true.
  #
  # If you use this in production, you're gonna have a bad time.

  def reload!
    @mutex ||= Mutex.new

    @mutex.synchronize do
      self.class.erase! [self.class.source_file],
                        [self.class.name.split("::").last],
                        self.class.namespace

      self.class.erase_dependencies!
      require self.class.source_file
      @app = self.class.source_class.new @rack_app, @logger
    end
  end


  ##
  # Default Rack call method.

  def call env
    try_autoreload(env)

    if @app.route!(env)
      @app.call!(env)

    elsif @app.static!(env)
      @app.call_static(env)

    elsif @rack_app
      @rack_app.call(env)

    else
      @app.call!(env)
    end
  end


  ##
  # Check if autoreload is needed and reload.

  def try_autoreload env
    return if env[GIN_RELOADED] || !autoreload
    env[GIN_RELOADED] = true
    reload!
  end


  ##
  # Call App instance stack without static file lookup or reloading.

  def call! env
    if env[GIN_STACK]
      dispatch env, env[GIN_CTRL], env[GIN_ACTION]

    else
      env[GIN_STACK] = true
      with_log_request(env) do
        @stack.call env
      end
    end
  end


  ##
  # Returns a static file Rack response Array from the given gin.static
  # env filename.

  def call_static env
    with_log_request(env) do
      error_delegate.exec(self, env){ send_file env[GIN_STATIC] }
    end
  end


  ##
  # Check if the request is for a static file and set the gin.static env
  # variable to the filepath.

  def static! env
    filepath = %w{GET HEAD}.include?(env[REQ_METHOD]) &&
               asset(env[PATH_INFO])

    filepath ? (env[GIN_STATIC] = filepath) :
                env.delete(GIN_STATIC)

    !!env[GIN_STATIC]
  end


  ##
  # Check if the request routes to a controller and action and set
  # gin.controller, gin.action, gin.path_query_hash,
  # and gin.http_route env variables.

  def route! env
    http_route = "#{env[REQ_METHOD]} #{env[PATH_INFO]}"
    return true if env[GIN_ROUTE] == http_route

    env[GIN_CTRL], env[GIN_ACTION], env[GIN_PATH_PARAMS] =
      router.resources_for env[REQ_METHOD], env[PATH_INFO]

    env[GIN_ROUTE] = http_route

    !!(env[GIN_CTRL] && env[GIN_ACTION])
  end


  STATIC_PATH_CLEANER = %r{\.+/|/\.+}  #:nodoc:

  ##
  # Check if an asset exists.
  # Returns the full path to the asset if found, otherwise nil.
  # Does not support ./ or ../ for security reasons.

  def asset path
    path = path.gsub STATIC_PATH_CLEANER, ""

    filepath = File.expand_path(File.join(public_dir, path))
    return filepath if File.file? filepath

    filepath = File.expand_path(File.join(Gin::PUBLIC_DIR, path))
    return filepath if File.file? filepath
  end


  ##
  # Dispatch the Rack env to the given controller and action.

  def dispatch env, ctrl, action
    raise Gin::NotFound,
      "No route exists for: #{env[REQ_METHOD]} #{env[PATH_INFO]}" unless
      ctrl && action

    env[GIN_CTRL] = ctrl.new(self, env)
    env[GIN_CTRL].call_action action

  rescue ::Exception => err
    handle_error(err, env)
  end


  ##
  # Handle error with error_delegate if available, otherwise re-raise.

  def handle_error err, env
    delegate = error_delegate

    begin
      delegate.exec(self, env){ handle_error(err) }

    rescue ::Exception => err
      delegate = Gin::Controller and retry unless delegate == Gin::Controller
      raise
    end
  end


  private


  LOG_FORMAT = %{%s - %s [%s] "%s %s%s" %s %d %s %0.4f %s\n}.freeze #:nodoc:
  TIME_FORMAT = "%d/%b/%Y %H:%M:%S".freeze #:nodoc:

  def log_request env, resp
    now  = Time.now
    time = now - env[GIN_TIMESTAMP] if env[GIN_TIMESTAMP]

    ctrl, action = env[GIN_CTRL].class, env[GIN_ACTION]
    target = "#{ctrl}##{action}" if ctrl && action

    @logger << ( LOG_FORMAT % [
        env[FWD_FOR] || env[REMOTE_ADDR] || "-",
        env[REMOTE_USER] || "-",
        now.strftime(TIME_FORMAT),
        env[REQ_METHOD],
        env[PATH_INFO],
        env[QUERY_STRING].to_s.empty? ? "" : "?#{env[QUERY_STRING]}",
        env[HTTP_VERSION] || "HTTP/1.1",
        resp[0],
        resp[1][CNT_LENGTH] || "-",
        time || "-",
        target || "-" ] )
  end


  def with_log_request env
    env[GIN_TIMESTAMP] ||= Time.now
    resp = yield
    log_request env, resp
    resp
  end


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
    require 'rack-protection' unless defined?(Rack::Protection)

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
