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


  def self.setup   #:nodoc:
    caller_line = caller.find{|line| !CALLERS_TO_IGNORE.any?{|m| line =~ m} }
    filepath = File.expand_path(caller_line.split(/:\d+:in `/).first)
    dir = File.dirname(filepath)

    @source_file  = filepath
    @source_class = self.to_s
    @templates    = Gin::Cache.new
    @md5s         = Gin::Cache.new
    @reload_mutex = Mutex.new
    @autoreload   = nil
    @instance     = nil

    @options = {}
    @options[:root_dir]       = dir
    @options[:asset_dirs]     = %w{assets lib/assets vendor/**/assets}
    @options[:environment]    = ENV['RACK_ENV'] || ENV_DEV
    @options[:error_delegate] = Gin::Controller
    @options[:middleware]     = []
    @options[:logger]         = Logger.new($stdout)
    @options[:router]         = Gin::Router.new
    @options[:session_secret] = SESSION_SECRET
    @options[:protection]     = false
    @options[:sessions]       = false
    @options[:config_reload]  = false
    @options[:layout]         = :layout
    @options[:template_engines] = Tilt.mappings.merge(nil => [Tilt::ERBTemplate])
  end


  ##
  # Create a new instance of the app and call it.

  def self.call env
    @instance ||= self.new
    @instance.call env
  end


  ##
  # Hash of the full Gin::App configuration.
  # Result of using class-level setter methods such as Gin::App.environment.

  def self.options
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
    @autoreload = val unless val.nil?
    reload = @autoreload.nil? ? self.environment == ENV_DEV : @autoreload

    if reload
      Object.send :require, 'gin/reloadable' unless defined?(Gin::Reloadable)
      include Gin::Reloadable                unless self < Gin::Reloadable
    end

    reload
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
  # Get or append directories for the asset pipeline to find files.
  # Files are added recursively from each directory.
  #
  #   # Default asset directories
  #   assets_dir
  #   #=> ["assets", "lib/assets", "vendor/**/assets"]
  #
  #   assets_dir 'foo/assets', '/usr/local/other_repo/assets'
  #   #=> ["assets", "lib/assets", "vendor/**/assets", "foo/assets", "/usr/local/other_repo/assets"]

  def self.assets_dir *dirs
    (@options[:asset_dirs] ||= []).concat(dirs) if dirs
    @options[:asset_dirs]
  end


  ##
  # Get or set asset pipeline functionality.
  # Off when set to false, on when set to true. A Sprocket::Environment instance
  # may also be passed if a more fine-tuned setup is required.
  #
  #   # Turn off asset pipelining
  #   asset_pipeline false
  #
  #   # Turn on asset pipelining
  #   asset_pipeline true
  #
  #   # Custom set asset pipeline
  #   sprockets = Sprockets::Environment.new('/usr/local/assets_repo')
  #   sprockets.css_compressor = Sprockets::SassCompressor
  #   asset_pipeline sprockets
  #
  # Asset pipelining is only turned on if the asset directories are present.

  def self.asset_pipeline val=nil
    @options[:asset_pipeline] = val unless val.nil?
    @options[:asset_pipeline]
  end


  ##
  # Get or set whether the asset pipeline should compress CSS and Javascript.
  # Defaults to true in production. Defaults to false when not in production.
  # Default compressors used are sass and uglifier.

  def self.asset_compression val=nil
    @options[:asset_compression] = val unless val.nil?
    @options[:asset_compression]
  end


  def self.make_config opts={}  # :nodoc:
    Gin::Config.new opts[:environment] || self.environment,
        :dir =>    opts[:config_dir]    || self.config_dir,
        :logger => opts[:logger]        || self.logger,
        :ttl =>    opts[:config_reload] || self.config_reload
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
  #   # access from App class
  #   CACHE = Memcache.new( MyApp.config['memcache.host'] )
  #
  # The config object is shared across all instances of the App and has
  # thread-safety built-in.

  def self.config
    @options[:config] ||= make_config
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
    if String === dir
      @options[:config_dir] = dir
      @options[:config].dir = dir if @options[:config]
    end

    @options[:config_dir] || File.join(self.root_dir, "config")
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
    unless ttl.nil?
      @options[:config_reload] = ttl
      @options[:config].ttl = ttl if @options[:config]
    end
    @options[:config_reload]
  end


  ##
  # Set the default templating engine to use for various
  # file extensions, or by default:
  #   # Default for .markdown and .md files
  #   default_template Tilt::MarukuTemplate, 'markdown', 'md'
  #
  #   # Default for files without preset default
  #   default_template Tilt::BlueClothTemplate

  def self.default_template klass, *extensions
    extensions = [nil] if extensions.empty?
    extensions.each{|ext|
      (@options[:template_engines][ext] ||= []).unshift klass }
  end


  ##
  # Get or set the current environment name,
  # by default ENV ['RACK_ENV'], or "development".

  def self.environment env=nil
    if env
      @options[:environment] = env
      @options[:config].environment = env if @options[:config]
    end
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
  # Get or et the Host header on responses if not set by the called action.
  # If the enforce options is given, the app will only respond to requests that
  # explicitely match the specified host, or regexp.
  # This is useful for running multiple apps on the same middleware stack that
  # might have conflicting routes, or need explicit per-host routing (such
  # as an admin app).
  #   hostname 'host.com'
  #   hostname 'admin.host.com:443', :enforce => true
  #   hostname 'admin.host.com', :enforce => /^admin\.(localhost|host\.com)/

  def self.hostname host=nil, opts={}
    @options[:host] = {:name => host}.merge(opts) if host
    @options[:host][:name] if @options[:host]
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
    @options[:layouts_dir] || File.join(root_dir, 'layouts')
  end


  ##
  # Get or set the logger for your application. Loggers must respond
  # to the << method.

  def self.logger new_logger=nil
    if new_logger
      @options[:logger] = new_logger
      @options[:config].logger = new_logger if @options[:config]
    end
    @options[:logger]
  end


  ##
  # Cache of file md5s shared across all instances of an App class.
  # Used for static asset versioning.

  def self.md5s
    @md5s
  end


  ##
  # List of internal app middleware.

  def self.middleware
    @options[:middleware]
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
    @options[:public_dir] || File.join(root_dir, "public")
  end


  def self.reload_mutex # :nodoc:
    @reload_mutex
  end


  ##
  # Get or set the root directory of the application.
  # Defaults to the app file's directory.

  def self.root_dir dir=nil
    @options[:root_dir] = File.expand_path(dir) if dir
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
  # Cache of precompiled templates, shared across all instances of a
  # given App class.

  def self.templates
    @templates
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
    @options[:views_dir] || File.join(root_dir, 'views')
  end


  opt_reader :protection, :sessions, :session_secret, :middleware
  opt_reader :error_delegate, :router, :logger
  opt_reader :layout, :layouts_dir, :views_dir, :template_engines
  opt_reader :root_dir, :public_dir, :environment

  class_proxy :mime_type, :md5s, :templates, :reload_mutex, :autoreload

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

    @options = {
      :config_dir  =>  self.class.config_dir,
      :public_dir  =>  self.class.public_dir,
      :layouts_dir => self.class.layouts_dir,
      :views_dir   =>   self.class.views_dir,
      :config      =>      self.class.config
    }.merge(self.class.options).merge(options)

    @options[:asset_pipeline_compression] = production? if
      @options[:asset_pipeline_compression].nil?

    @options[:config] = self.class.make_config(@options) if
      @options[:environment] != @options[:config].environment ||
      @options[:config_dir] != @options[:config].dir ||
      @options[:config_reload] != @options[:config].ttl

    validate_all_controllers!

    @app   = self
    @stack = build_app Rack::Builder.new
    setup_asset_pipeline
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
  #   # access from App instance
  #   @app.config['memcache.host']
  #
  # The config object is shared across all instances of the App and has
  # thread-safety built-in.

  def config
    @options[:config]
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
  # Returns the default asset host.

  def asset_host
    asset_host_for(nil)
  end


  ##
  # Returns the first 8 bytes of the asset file's md5.
  # File path is assumed relative to the public_dir.

  def asset_version path
    if asset_pipeline
      asset = asset_pipeline.find_asset(path)
      return asset.digest if asset
    end

    path = File.expand_path(File.join(public_dir, path))
    md5(path)
  end


  ##
  # Returns the url to an asset, including predefined asset CDN hosts if set,
  # and/or asset pipeline path.

  def asset_url name
    if asset_pipeline
      asset = asset_pipeline.find_asset(name)
      name  = asset.digest_path if asset
    end

    name = Gin.unescape_path(name)
    url  = File.join(asset_host_for(name).to_s, name)

    if !asset && url !~ %r{^https?://}
      hash = asset_version(url)
      url.sub!(%r{(\.[^.]+)?$}, "-#{hash}" + '\1') if hash
    end

    url
  end


  ##
  # Returns a Sprockets::Environment instance if asset pipelining is being used,
  # otherwise nil.

  def asset_pipeline
    @sprockets
  end


  STATIC_PATH_CLEANER = %r{\.+/|/\.+}  #:nodoc:
  STATIC_MD5_CLEANER = %r{-([0-9a-f]{7,40})(\.[^.]+)$} #:nodoc:

  ##
  # Check if an asset exists in the public directory, or the asset pipeline.
  #
  # Returns the full path to the asset if found, otherwise nil.
  # Does not support ./ or ../ for security reasons,
  # and ignores asset fingerprint.
  #
  #   # Asset in public directory
  #   asset '/img/foo.jpg'
  #   #=> '/usr/local/.../public/img/foo.jpg
  #
  #   # Asset in public directory with fingerprint.
  #   asset '/img/foo-f89a0ed613f.jpg'
  #   #=> '/usr/local/.../public/img/foo.jpg
  #
  #   # Asset in asset pipeline.
  #   asset '/foo-f89a0ed613f.jpg'
  #   #=> '/usr/local/.../assets/img/foo.jpg

  def asset path
    path  = Gin.escape_path(path)
    path.gsub!(STATIC_PATH_CLEANER, '')
    apath = path.sub(STATIC_MD5_CLEANER, '\2')

    if asset_pipeline
      asset = asset_pipeline.find_asset(apath)
      return asset.pathname.to_s if asset
    end

    filepath = File.expand_path(File.join(public_dir, path))
    return filepath if File.file? filepath

    filepath = File.expand_path(File.join(public_dir, apath))
    return filepath if File.file? filepath

    filepath = File.expand_path(File.join(Gin::PUBLIC_DIR, path))
    return filepath if File.file? filepath

    filepath = File.expand_path(File.join(Gin::PUBLIC_DIR, apath))
    return filepath if File.file? filepath
  end


  MD5 = RUBY_PLATFORM =~ /darwin/ ? 'md5 -q' : 'md5sum' #:nodoc:

  ##
  # Returns the first 8 characters of a file's MD5 hash.
  # Values are cached for future reference.

  def md5 path
    return unless File.file?(path)
    self.md5s[path] ||= `#{MD5} #{path}`[0...8]
  end


  ##
  # The name defined by App.hostname.

  def hostname
    @options[:host][:name] if @options[:host]
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
    templates.cache([path, engine]) do
      if file = template_files(path).first
        ext = File.extname(file)
        ext = ext.empty? ? nil : ext[1..-1]
        engine ||= template_engines[ext].first
        engine.new(file) if engine
      end
    end
  end


  ##
  # Returns an Array of file paths that match a valid path and maps
  # to a known template engine.
  #   app.template_files 'views/foo'
  #   #=> ['views/foo.erb', 'views/foo.md']

  def template_files path
    exts = template_engines.keys.map{|e| "." << e if e }.join(",")
    Dir["#{path}{#{exts}}"]
  end


  ##
  # Used for auto reloading the whole app in development mode.
  # Will only reload if Gin::App.autoreload is set to true.
  #
  # If you use this in production, you're gonna have a bad time.

  def reload!
    reload_mutex.synchronize do
      self.class.erase_dependencies!

      if File.extname(self.class.source_file) != ".ru"
        self.class.erase! [self.class.source_file],
                          [self.class.name.split("::").last],
                          self.class.namespace
        require self.class.source_file
      end

      @app = self.class.source_class.new @rack_app
    end
  end


  ##
  # Default Rack call method.

  def call env
    try_autoreload(env)

    valid_host = valid_host?(env)

    resp =
      if valid_host && @app.route!(env)
        @app.call!(env)

      elsif valid_host && @app.static!(env)
        @app.call_static(env)

      elsif @rack_app
        @rack_app.call(env)

      elsif !valid_host
        bt  = caller
        msg = "No route for host '%s:%s'" % [env[SERVER_NAME], env[SERVER_PORT]]
        err = Gin::BadRequest.new(msg)
        err.set_backtrace(bt)
        handle_error(err, env)

      else
        @app.call!(env)
      end

    resp[1][HOST_NAME] ||=
      (hostname || env[SERVER_NAME]).sub(/(:[0-9]+)?$/, ":#{env[SERVER_PORT]}")

    resp
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
      dispatch env

    else
      env[GIN_STACK] = true
      with_log_request(env) do
        @stack.call env
      end
    end
  end


  ##
  # Returns a static file Rack response Array from the filename set
  # in env['gin.static'].

  def call_static env
    with_log_request(env) do
      if asset_pipeline && asset_pipeline[env[GIN_STATIC]]
        asset_pipeline.call(env)
      else
        error_delegate.exec(self, env){ send_file env[GIN_STATIC] }
      end
    end
  end


  ##
  # Check if the request is for a static file and set the gin.static env
  # variable to the filepath. Returns true if request is to a static asset,
  # otherwise false.

  def static! env
    filepath = %w{GET HEAD}.include?(env[REQ_METHOD]) &&
               asset(env[PATH_INFO])

    filepath ? (env[GIN_STATIC] = filepath) :
                env.delete(GIN_STATIC)

    !!env[GIN_STATIC]
  end


  ##
  # Check if the request routes to a controller and action and set
  # gin.target, gin.path_query_hash, and gin.http_route env variables.
  # Returns true if a route is found, otherwise false.

  def route! env
    http_route = "#{env[REQ_METHOD]} #{env[PATH_INFO]}"
    return true if env[GIN_ROUTE] == http_route

    env[GIN_TARGET], env[GIN_PATH_PARAMS] =
      router.resources_for env[REQ_METHOD], env[PATH_INFO]

    env[GIN_ROUTE] = http_route

    !!env[GIN_TARGET]
  end


  def rewrite_env env, *args  # :nodoc:
    headers = args.pop if Hash === args.last && Hash === args[-2] && args[-2] != args[-1]
    params  = args.pop if Hash === args.last

    route = if String === args.first
              verb = (headers && headers[REQ_METHOD] || 'GET').upcase
              Gin::Router::Route.new(verb, args[0])
            else
              @app.router.route_to(*args)
            end

    new_env = env.dup
    new_env.delete_if{|k, v| k.start_with?('gin.') }
    new_env[GIN_RELOADED]  = env[GIN_RELOADED]
    new_env[GIN_TIMESTAMP] = env[GIN_TIMESTAMP]

    new_env.merge!(headers) if headers
    route.to_env(params, new_env)
  end


  ##
  # Rewrites the given Rack env and processes the new request.
  # You're probably looking for Gin::Controller#rewrite or
  # Gin::Controller#reroute.

  def rewrite! env, *args
    new_env = rewrite_env(env, *args)

    logger << "[REWRITE] %s %s -> %s %s\n" %
      [env[REQ_METHOD], env[PATH_INFO], new_env[REQ_METHOD], new_env[PATH_INFO]]

    call(new_env)
  end


  ##
  # Dispatch the Rack env to the given controller and action.

  def dispatch env
    raise Gin::NotFound,
      "No route exists for: #{env[REQ_METHOD]} #{env[PATH_INFO]}" unless
      env[GIN_TARGET]

    env[GIN_APP] = self
    env[GIN_TARGET][0].call(env)

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

    target = request_target_name(env, resp)

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


  def request_target_name env, resp
    if env[GIN_TARGET]
      if Gin::Mountable === env[GIN_TARGET][0]
        env[GIN_TARGET][0].display_name(env[GIN_TARGET][1])
      else
        "#{env[GIN_TARGET][0].inspect}->#{env[GIN_TARGET][1].inspect}"
      end
    elsif resp[2].respond_to?(:path)
      resp[2].path
    elsif !(Array === resp[2]) || !resp[2].empty?
      "<stream>"
    end
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


  def setup_asset_pipeline
    return unless @options[:asset_dirs] && !@options[:asset_dirs].empty? &&
                  !@options[:asset_pipeline] == false

    Gin.use_lib 'sprockets'
    @sprockets = Sprockets::Environment === @options[:asset_pipeline] ?
                   @options[:asset_pipeline] :
                   Sprockets::Environment.new(root_dir)

    @options[:asset_dirs].each do |spath|
      spath = File.join(@sprockets.root, spath) unless spath.start_with?(?/)
      Dir[File.join(spath, '**/')].each do |path|
        @sprockets.append_path path
      end
    end

    if @sprockets.paths.empty?
      @sprockets = nil
      return
    end

    if @options[:asset_compression]
      @sprockets.js_compressor  ||= Sprockets::UglifierCompressor
      @sprockets.css_compressor ||= Sprockets::SassCompressor
    end
  end


  ##
  # Make sure all controller actions have a route, or raise a RouterError.

  def validate_all_controllers!
    actions_map = {}

    router.each_route do |route, ctrl, action|
      (actions_map[ctrl] ||= []) << action
    end

    actions_map.each do |ctrl, actions|
      next unless Gin::Mountable === ctrl
      ctrl.verify_mount!

      not_mounted = ctrl.actions - actions
      raise Gin::RouterError, "#{ctrl.display_name(not_mounted[0])} has no route" unless
        not_mounted.empty?

      extra_mounted = actions - ctrl.actions
      raise Gin::RouterError, "#{ctrl.display_name(extra_mounted[0])} is not an action" unless
        extra_mounted.empty?
    end
  end


  def valid_host? env
    return true unless @options[:host] && @options[:host][:enforce]

    name, port = @options[:host][:name].split(":", 2)

    if @options[:host][:enforce] == true
      name == env[SERVER_NAME] && (port.nil? || port == env[SERVER_PORT])
    else
      @options[:host][:enforce] === "#{env[SERVER_NAME]}:#{env[SERVER_PORT]}" ||
        @options[:host][:enforce] === env[SERVER_NAME] &&
          (port.nil? || port == env[SERVER_PORT])
    end
  end


  setup
end
