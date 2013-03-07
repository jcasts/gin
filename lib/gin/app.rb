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
    :path_params => 'gin.path_query_hash'.freeze,
    :reloaded    => 'gin.reloaded'.freeze
  }.freeze


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
    filepath = File.expand_path(caller_line.split(/:\d+:in `</).first)
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

  def self.autoreload val=nil
    @autoreload = val unless val.nil?
    @autoreload = development? if @autoreload.nil?

    if @autoreload && (!defined?(Gin::Reloadable) || !include?(Gin::Reloadable))
      require 'gin/reloadable'
      include Gin::Reloadable
    end

    @autoreload
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
  # hash for options. Defaults to true.

  def self.sessions opts=nil
    @session = opts unless opts.nil?
    @session = true if @session.nil?
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
  # hash for options. Defaults to true.

  def self.protection opts=nil
    @protection = opts unless opts.nil?
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


  class_proxy :protection, :sessions, :session_secret, :middleware, :autoreload
  class_proxy :error_delegate, :router
  class_proxy :root_dir, :public_dir
  class_proxy :mime_type, :asset_host_for, :asset_host, :asset_version
  class_proxy :environment, :development?, :test?, :staging?, :production?
  class_proxy :load_config, :config, :config_dir

  # Application logger. Defaults to log to $stdout.
  attr_accessor :logger

  # App to fallback on if Gin::App is used as middleware and no route is found.
  attr_reader :rack_app, :stack


  ##
  # Create a new Rack-mountable Gin::App instance, with an optional
  # rack_app and logger.

  def initialize rack_app=nil, logger=nil
    load_config

    if !rack_app.respond_to?(:call) && rack_app.respond_to?(:log) && logger.nil?
      @rack_app = nil
      @logger   = rack_app
    else
      @rack_app = rack_app
      @logger   = Logger.new $stdout
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
    return unless autoreload
    self.class.erase! [self.class.source_file],
                      [self.class.name.split("::").last],
                      self.class.namespace

    self.class.erase_dependencies!
    Object.send(:require, self.class.source_file)
    @app = self.class.source_class.new @rack_app, @logger
  end


  ##
  # Default Rack call method.

  def call env
    if autoreload && !env[RACK_KEYS[:reloaded]]
      env[RACK_KEYS[:reloaded]] = true
      reload!
      @app.call env

    elsif env[RACK_KEYS[:stack]]
      env.delete RACK_KEYS[:stack]
      @app.call! env

    else
      env[RACK_KEYS[:stack]] = true
      @stack.call env
    end
  end


  ##
  # Call App instance without internal middleware.

  def call! env
    if filename = static?(env)
      return error_delegate.exec(self, env){ send_file filename }
    end

    ctrl, action, env[RACK_KEYS[:path_params]] =
      router.resources_for env['REQUEST_METHOD'], env['PATH_INFO']

    dispatch env, ctrl, action
  end


  STATIC_PATH_CLEANER = %r{\.+/|/\.+}  #:nodoc:

  ##
  # Check if the request is for a static file.

  def static? env
    %w{GET HEAD}.include?(env['REQUEST_METHOD']) && asset(env['PATH_INFO'])
  end


  ##
  # Check if an asset exists.
  # Returns the full path to the asset if found, otherwise nil.

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
      "No route exists for: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}" unless
      ctrl && action

    ctrl.new(self, env).call_action action

  rescue Gin::NotFound => err
    @rack_app ? @rack_app.call(env) : handle_error(err, env)

  rescue ::Exception => err
    handle_error(err, env)
  end


  ##
  # Handle error with error controller if available, otherwise re-raise.

  def handle_error err, env
    delegate = error_delegate

    begin
      trace = Gin.app_trace(Array(err.backtrace)).join("\n")
      logger.error("#{err.class.name}: #{err.message}\n#{trace}")
      delegate.exec(self, env){ handle_error(err) }

    rescue ::Exception => err
      delegate = Gin::Controller and retry unless delegate == Gin::Controller
      raise
    end
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
