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
    /lib\/gin(\/(.*?))?\.rb/,           # all gin code
    /lib\/tilt.*\.rb/,                  # all tilt code
    /^\(.*\)$/,                         # generated code
    /rubygems\/custom_require\.rb/,     # rubygems require hacks
    /active_support/,                   # active_support require hacks
    /bundler(\/runtime)?\.rb/,          # bundler require hacks
    /<internal:/,                       # internal in ruby >= 1.9.2
    /src\/kernel\/bootstrap\/[A-Z]/     # maglev kernel files
  ]


  def self.inherited subclass   #:nodoc:
    subclass.setup
  end


  def self.setup   #:nodoc
    caller_line = caller.find{|line| !CALLERS_TO_IGNORE.any?{|m| line =~ m} }
    filepath = File.expand_path(caller_line.split(/:\d+:in `/).first)
    dir = File.dirname(filepath)

    @source_file  = filepath
    @source_class = self.to_s

    @options = {}
    @options[:root_dir]       = dir
    @options[:environment]    = ENV['RACK_ENV'] || ENV_DEV
    @options[:error_delegate] = Gin::Controller
    @options[:middleware]     = []
    @options[:logger]         = $stdout
    @options[:router]         = Gin::Router.new
    @options[:session_secret] = SESSION_SECRET
    @options[:protection]     = false
    @options[:sessions]       = false
    @options[:config_reload]  = false
    @options[:layout]         = :layout
    @options[:template_engines] = Tilt.mappings.merge(nil => Tilt::ERBTemplate)
  end


  ##
  # Create a new intance of the app and call it.

  def self.call env
    @instance ||= self.new
    @instance.call env
  end


  ##
  # Hash of the full Gin::App configuration.
  # Result of using class-level setter methods such as Gin::App.environment.
  # Defaults are assigned for values that haven't been set.

  def self.options
    self.autoreload
    self.public_dir
    self.layouts_dir
    self.views_dir
    @options
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
  # Enable or disable auto-app reloading.
  # On by default in development mode.
  #
  # In order for an app to be reloadable, the libs and controllers must be
  # required from the Gin::App class context, or use MyApp.require("lib").
  #
  # Gin::App class reloading is not supported for applications defined in
  # the config.ru file. Dependencies will, however, still be reloaded.
  #
  # Autoreload must be enabled before any calls to Gin::App.require for
  # those files to be reloaded.
  #
  #   class MyApp < Gin::App
  #
  #     # Only reloaded in development mode
  #     require 'nokogiri'
  #
  #     autoreload false
  #     # Never reloaded
  #     require 'static_thing'
  #
  #     autoreload true
  #     # Reloaded every request
  #     require 'my_app/home_controller'
  #   end

  def self.autoreload val=nil
    @options[:autoreload] = val unless val.nil?
    @options[:autoreload] = self.environment == ENV_DEV if @options[:autoreload].nil?

    if @options[:autoreload]
      Object.send :require, 'gin/reloadable' unless defined?(Gin::Reloadable)
      include Gin::Reloadable                unless self < Gin::Reloadable
    end

    @options[:autoreload]
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
  # Get or set the CDN asset host (and path).
  # If block is given, evaluates the block on every read.

  def self.asset_host host=nil, &block
    @options[:asset_host] = host  if host
    @options[:asset_host] = block if block_given?
    @options[:asset_host]
  end


  ##
  # Get or set the path to the config directory.
  # Defaults to "<root_dir>/config"
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
    @options[:config_dir] = dir if String === dir
    @options[:config_dir]
  end


  ##
  # Get or set the config max age for auto-reloading in seconds.
  # Turns config reloading off if set to false. Defaults to false.
  # Config only gets reloaded on demand.
  #
  #   # Set to 10 minutes
  #   config_reload 600
  #
  #   # Set to never reload
  #   config_reload false

  def self.config_reload ttl=nil
    @options[:config_reload] = ttl unless ttl.nil?
    @options[:config_reload]
  end


  ##
  # Set the default templating engine to use for various
  # file extensions, or by default:
  #   # Default for .markdown and .md files
  #   default_template Tilt::MarukuTemplate, '.markdown', '.md'
  #
  #   # Default for files without preset default
  #   default_template Tilt::BlueClothTemplate

  def self.default_template klass, *extensions
    extensions = [nil] if extensions.empty?
    extensions.each{|ext| @options[:template_engines][ext] = klass }
  end


  ##
  # Get or set the current environment name,
  # by default ENV ['RACK_ENV'], or "development".

  def self.environment env=nil
    @options[:environment] = env if env
    @options[:environment]
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
    @options[:error_delegate] = ctrl if ctrl
    @options[:error_delegate]
  end


  ##
  # Get or set the layout name. Layout file location is assumed to be in
  # the views_dir. If the views dir has a controller wildcard '*', the layout
  # is assumed to be one level above the controller-specific directory.
  #
  # Defaults to :layout.

  def self.layout name=nil
    @options[:layout] = name if name
    @options[:layout]
  end


  ##
  # Get or set the directory for view layouts.
  # Defaults to the "<root_dir>/layouts".

  def self.layouts_dir dir=nil
    @options[:layouts_dir] = dir if dir
    @options[:layouts_dir] ||= File.join(root_dir, 'layouts')
  end


  ##
  # Get or set the logger for your application. Logger instance must respond
  # to the << method.

  def self.logger new_logger=nil
    @options[:logger] = new_logger if new_logger
    @options[:logger]
  end


  ##
  # List of internal app middleware.

  def self.middleware
    @options[:middleware]
  end


  ##
  # Use rack-protection or not. Supports assigning
  # hash for options. Defaults to false.

  def self.protection opts=nil
    @options[:protection] = opts unless opts.nil?
    @options[:protection]
  end


  ##
  # Get or set the path to the public directory.
  # Defaults to "<root_dir>/public"

  def self.public_dir dir=nil
    @options[:public_dir] = dir if dir
    @options[:public_dir] ||= File.join(root_dir, "public")
  end


  ##
  # Get or set the root directory of the application.
  # Defaults to the app file's directory.

  def self.root_dir dir=nil
    @options[:root_dir] = dir if dir
    @options[:root_dir]
  end


  ##
  # Router instance that handles mapping Rack-env -> Controller#action.

  def self.router
    @options[:router]
  end


  ##
  # Use rack sessions or not. Supports assigning
  # hash for options. Defaults to false.

  def self.sessions opts=nil
    @options[:sessions] = opts unless opts.nil?
    @options[:sessions]
  end


  ##
  # Get or set the session secret String.
  # Defaults to a new random value on boot.

  def self.session_secret val=nil
    @options[:session_secret] = val if val
    @options[:session_secret]
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
  # Get or set the path to the views directory.
  # The wildcard '*' will be replaced by the controller name.
  #
  # Defaults to "<root_dir>/views"

  def self.views_dir dir=nil
    @options[:views_dir] = dir if dir
    @options[:views_dir] ||= File.join(root_dir, 'views')
  end


  opt_reader :protection, :sessions, :session_secret, :middleware, :autoreload
  opt_reader :error_delegate, :router, :logger
  opt_reader :layout, :layouts_dir, :views_dir, :template_engines
  opt_reader :root_dir, :public_dir, :environment

  class_proxy :mime_type

  # App to fallback on if Gin::App is used as middleware and no route is found.
  attr_reader :rack_app

  # Options applied to the Gin::App instance. Typically a result of
  # class-level configuration methods, such as Gin::App.environment.
  attr_reader :options

  # Internal Rack stack.
  attr_reader :stack


  ##
  # Create a new Rack-mountable Gin::App instance, with an optional
  # rack_app and options.

  def initialize rack_app=nil, options={}
    if Hash === rack_app
      options   = rack_app
      @rack_app = nil
    else
      @rack_app = rack_app
    end

    @options = self.class.options.merge(options)

    validate_all_controllers!

    @config = Gin::Config.new environment,
        dir:    (@options[:config_dir] || File.join(root_dir, "config")),
        logger: logger,
        ttl:    @options[:config_reload]

    @reload_mutex = Mutex.new

    @app       = self
    @stack     = build_app Rack::Builder.new
    @templates = Gin::Cache.new
    @md5s      = Gin::Cache.new
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
  #   config['memcache.host']

  def config
    @config
  end


  ##
  # Check if running in development mode.

  def development?
    self.environment == ENV_DEV
  end


  ##
  # Check if running in test mode.

  def test?
    self.environment == ENV_TEST
  end


  ##
  # Check if running in staging mode.

  def staging?
    self.environment == ENV_STAGE
  end


  ##
  # Check if running in production mode.

  def production?
    self.environment == ENV_PROD
  end


  ##
  # Returns the asset host for a given asset name. This is useful when assigning
  # a block for the asset_host. The asset_name argument is passed to the block.

  def asset_host_for asset_name
     @options[:asset_host].respond_to?(:call) ?
      @options[:asset_host].call(asset_name) : @options[:asset_host]
  end


  ##
  # Returns the generic asset host.

  def asset_host
    asset_host_for(nil)
  end


  ##
  # Returns the first 8 bytes of the asset file's md5.
  # File path is assumed relative to the public_dir.

  def asset_version path
    path = File.expand_path(File.join(public_dir, path))
    md5(path)
  end


  MD5 = RUBY_PLATFORM =~ /darwin/ ? 'md5 -q' : 'md5sum' #:nodoc:

  ##
  # Returns the first 8 characters of a file's MD5 hash.
  # Values are cached for future reference.

  def md5 path
    return unless File.file?(path)
    @md5s[path] ||= `#{MD5} #{path}`[0...8]
  end


  ##
  # Returns the tilt template for the given template name.
  # Returns nil if no template file is found.
  #   template_for 'user/show'
  #   #=> <Tilt::ERBTemplate @file="views/user/show.erb" ...>
  #
  #   template_for 'user/show.haml'
  #   #=> <Tilt::HamlTemplate @file="views/user/show.haml" ...>
  #
  #   template_for 'non-existant'
  #   #=> nil

  def template_for path, engine=nil
    @templates.cache([path, engine]) do
      if file = Dir["#{path}{,#{template_engines.keys.join(",")}}"].first
        ext = File.extname(file)
        ext = nil if ext.empty?
        engine ||= template_engines[ext]
        engine.new(file) if engine
      end
    end
  end


  ##
  # Used for auto reloading the whole app in development mode.
  # Will only reload if Gin::App.autoreload is set to true.
  #
  # If you use this in production, you're gonna have a bad time.

  def reload!
    @reload_mutex.synchronize do
      self.class.erase_dependencies!

      if File.extname(self.class.source_file) != ".ru"
        self.class.erase! [self.class.source_file],
                          [self.class.name.split("::").last],
                          self.class.namespace
        require self.class.source_file
      end

      @app = self.class.source_class.new @rack_app, @options
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

    logger << ( LOG_FORMAT % [
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
    opts = {}
    opts[:secret] = session_secret if session_secret
    opts.merge! sessions.to_hash if sessions.respond_to? :to_hash
    builder.use Rack::Session::Cookie, opts
  end


  def setup_protection builder
    return unless protection
    require 'rack-protection' unless defined?(Rack::Protection)

    opts = Hash === protection ? protection.dup : {}
    opts[:except] = Array opts[:except]
    opts[:except] += [:session_hijacking, :remote_token] unless sessions
    opts[:reaction] ||= :drop_session
    builder.use Rack::Protection, opts
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


  setup
end
