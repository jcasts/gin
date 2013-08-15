#  Gin controllers follow only a few rules:
#
#  * ALL instance methods are actions (put your helper methods in a module or
#    parent class not mounted to the app).
#  * Filters are defined by blocks passed to special class methods.
#  * Controller-level error handlers are defined by blocks passed to the 'error'
#    class method.
#
#  Gin controller actions are any instance method defined on the controller
#  class. The HTTP response body takes the value of the method's return value.
#
#  If the instance method takes arguments, matching params will be assigned to
#  them. A required argument with a missing param triggers a Gin::BadRequest
#  error, resulting in a 400 response.
#
#    class UserController < Gin::Controller
#      # Get params id and email
#      def show id, email=nil
#        ...
#      end
#    end
#
#  Gin actions also support Ruby 2.0 keyed arguments, which are more flexible
#  for assigning default values when dealing with missing params.
#
#    class UserController < Gin::Controller
#      def show(id, email: nil, full: false)
#        ...
#      end
#    end
#
#  Views are rendered by calling the 'view' method from a controller instance.
#  Views don't halt the action but return a String of the rendered view.
#  If a layout was set, the rendered view will include the layout.
#
#    class UserController < Gin::Controller
#      layout :user
#
#      def show id
#        # Renders <app.views_dir>/show_user.* with the layout <app.layouts_dir>/user.*
#        view :show_user
#      end
#
#      def tos
#        # Renders <app.views_dir>/tos.* with no layout
#        view :tos, :layout => false
#      end
#    end

class Gin::Controller
  extend  GinClass
  include Gin::Constants
  include Gin::Filterable
  include Gin::Errorable


  error Gin::NotFound, Gin::BadRequest, ::Exception do |err|
    trace = Gin.app_trace(Array(err.backtrace)).join("  \n")
    trace = "  " << trace << "\n\n" unless trace.empty?
    logger << "[ERROR] #{err.class.name}: #{err.message}\n#{trace}"

    status( err.respond_to?(:http_status) ? err.http_status : 500 )
    @response.headers.clear
    content_type :html
    body html_error_page(err)
  end


  def self.inherited subclass
    subclass.setup
    super
  end


  def self.setup   # :nodoc:
    @layout = nil
    @ctrl_name = Gin.underscore(self.to_s).gsub(/_?controller_?/,'')
  end

  setup


  ##
  # Array of action names for this controller.

  def self.actions
    instance_methods(false).map{|a| a.to_sym }
  end


  ##
  # String representing the controller name.
  # Underscores the class name and removes mentions of 'controller'.
  #   MyApp::FooController.controller_name
  #   #=> "my_app/foo"

  def self.controller_name new_name=nil
    @ctrl_name = new_name if new_name
    @ctrl_name
  end


  ##
  # Set or get the default content type for this Gin::Controller.
  # Default value is "text/html". This attribute is inherited.

  def self.content_type new_type=nil
    @content_type = new_type if new_type
    return @content_type if defined?(@content_type) && @content_type
    self.superclass.respond_to?(:content_type) &&
      self.superclass.content_type || "text/html"
  end


  ##
  # Execute arbitrary code in the context of a Gin::Controller instance.
  # Returns a Rack response Array.

  def self.exec app, env, &block
    inst = new(app, env)
    inst.invoke{ inst.instance_exec(&block) }
    inst.response.finish
  end


  ##
  # Get or set a layout for a given controller.
  # Value can be a symbol or filepath.
  # Layout file is expected to be in the Gin::App.layout_dir directory
  # Defaults to the parent class layout, or Gin::App.layout.

  def self.layout name=nil
    @layout = name if name
    return @layout if @layout
    return self.superclass.layout if self.superclass.respond_to?(:layout)
  end


  class_rproxy :controller_name, :actions

  # The Gin::App instance used by the controller. The App instance is meant for
  # read-only use. Writes are not thread-safe and at your own risk.
  attr_reader :app

  # Gin::Request instance representing the HTTP request.
  attr_reader :request

  # Gin::Response instance representing the HTTP response.
  attr_reader :response

  # The action that the HTTP request resolved to, based on the App's router.
  attr_reader :action

  # The Rack env hash.
  attr_reader :env


  def initialize app, env
    @app      = app
    @action   = nil
    @env      = env
    @request  = Gin::Request.new env
    @response = Gin::Response.new
  end


  def call_action action #:nodoc:
    invoke{ dispatch action }
    invoke{ handle_status(@response.status) }
    content_type self.class.content_type unless @response[CNT_TYPE]
    @response.finish
  end


  ##
  # Set or get the HTTP response status code.

  def status code=nil
    @response.status = code if code
    @response.status
  end


  ##
  # Get or set the HTTP response body.

  def body body=nil
    @response.body = body if body
    @response.body
  end


  ##
  # Accessor for @app.config.

  def config
    @app.config
  end


  ##
  # Get the normalized mime-type matching the given input.

  def mime_type type
    @app.mime_type type
  end


  ##
  # Get or set the HTTP response Content-Type header.
  #   content_type :json
  #   content_type 'application/json;charset=us-ascii'
  #   content_type :json, charset: 'us-ascii'

  def content_type type=nil, params={}
    return @response[CNT_TYPE] unless type

    default   = params.delete(:default)
    mime_type = mime_type(type) || default
    raise "Unknown media type: %p" % type if mime_type.nil?

    mime_type = mime_type.dup
    unless params.include? :charset
      params[:charset] = params.delete('charset') || 'UTF-8'
    end

    params.delete :charset if mime_type.include? 'charset'
    unless params.empty?
      mime_type << (mime_type.include?(';') ? ', ' : ';')
      mime_type << params.map do |key, val|
        val = val.inspect if val =~ /[";,]/
        "#{key}=#{val}"
      end.join(', ')
    end

    @response[CNT_TYPE] = mime_type
  end


  ##
  # Stop the execution of an action and return the response.
  # May be given a status code, string, header Hash, or a combination:
  #   halt 400, "Badly formed request"
  #   halt "Done early! WOOO!"
  #   halt 302, {'Location' => 'http://example.com'}, "You are being redirected"

  def halt *resp
    if @app.development?
      line = caller.find{|l| !l.start_with?(Gin::LIB_DIR) && !l.include?("/ruby/gems/")}
      logger << "[HALT] #{line}\n" if line
    end

    resp = resp.first if resp.length == 1
    throw :halt, resp
  end


  ##
  # Halt processing and return the error status provided.

  def error code, body=nil
    code, body     = 500, code if code.respond_to? :to_str
    @response.body = body unless body.nil?
    halt code
  end


  ##
  # Set the ETag header. If the ETag was set in a previous request
  # and matches the current one, halts the action and returns a 304
  # on GET and HEAD requests.

  def etag value, opts={}
    opts         = {:kind => opts} unless Hash === opts
    kind         = opts[:kind] || :strong
    new_resource = opts.fetch(:new_resource) { @request.post? }

    unless [:strong, :weak].include?(kind)
      raise ArgumentError, ":strong or :weak expected"
    end

    value = '"%s"' % value
    value = 'W/' + value if kind == :weak
    @response[ETAG] = value

    if (200..299).include?(status) || status == 304
      if etag_matches? @env[IF_NONE_MATCH], new_resource
        halt(@request.safe? ? 304 : 412)
      end

      if @env[IF_MATCH]
        halt 412 unless etag_matches? @env[IF_MATCH], new_resource
      end
    end
  end


  def etag_matches? list, new_resource=@request.post? #:nodoc:
    return !new_resource if list == '*'
    list.to_s.split(/\s*,\s*/).include? response[ETAG]
  end


  ##
  # Set multiple response headers with Hash.

  def headers hash=nil
    @response.headers.merge! hash if hash
    @response.headers
  end


  ##
  # Assigns a Gin::Stream to the response body, which is yielded to the block.
  # The block execution is delayed until the action returns.
  #   stream do |io|
  #     file = File.open "somefile", "rb"
  #     io << file.read(1024) until file.eof?
  #     file.close
  #   end

  def stream keep_open=false, &block
    scheduler = env[ASYNC_CALLBACK] ? EventMachine : Gin::Stream
    body Gin::Stream.new(scheduler, keep_open){ |out| yield(out) }
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
  # Access the request session.

  def session
    @request.session
  end


  ##
  # Access the request cookies.

  def cookies
    @request.cookies
  end


  ##
  # Set a cookie on the Rack response.
  #
  #   set_cookie "mycookie", "FOO", :expires => 600, :path => "/"
  #   set_cookie "mycookie", :expires => 600

  def set_cookie name, value=nil, opts={}
    if Hash === value
      opts = value
    else
      opts[:value] = value
    end

    @response.set_cookie name, opts
  end


  ##
  # Delete the response cookie with the given name.
  # Does not affect request cookies.

  def delete_cookie name
    @response.delete_cookie name
  end


  ##
  # Build a path to the given controller and action or route name,
  # with any expected params. If no controller is specified and the
  # current controller responds to the symbol given, uses the current
  # controller for path lookup.
  #
  #   path_to FooController, :show, :id => 123
  #   #=> "/foo/123"
  #
  #   # From FooController
  #   path_to :show, :id => 123
  #   #=> "/foo/123"
  #
  #   # Default named route
  #   path_to :show_foo, :id => 123
  #   #=> "/foo/123"

  def path_to *args
    return "#{args[0]}#{"?" << Gin.build_query(args[1]) if args[1]}" if String === args[0]
    args.unshift(self.class) if Symbol === args[0] &&
                                self.class.actions.include?(args[0])
    @app.router.path_to(*args)
  end


  ##
  # Build a URI to the given controller and action or named route, or path,
  # with any expected params.
  #   url_to "/foo"
  #   #=> "http://example.com/foo
  #
  #   url_to "/foo", :page => 2
  #   #=> "http://example.com/foo?page=foo
  #
  #   url_to MyController, :action
  #   #=> "http://example.com/routed/action
  #
  #   url_to MyController, :show, :id => 123
  #   #=> "http://example.com/routed/action/123
  #
  #   url_to :show_foo
  #   #=> "http://example.com/routed/action


  def url_to *args
    path = path_to(*args)

    return path if path =~ /\A[A-z][A-z0-9\+\.\-]*:/

    uri  = [host = ""]
    host << "http#{'s' if @request.ssl?}://"

    if @request.forwarded? || @request.port != (@request.ssl? ? 443 : 80)
      host << @request.host_with_port
    else
      host << @request.host
    end

    uri << @request.script_name.to_s
    uri << path
    File.join uri
  end

  alias to url_to


  ##
  # Send a 301, 302, or 303 redirect and halt.
  # Supports passing a full URI, partial path.
  #   redirect "http://google.com"
  #   redirect "/foo"
  #   redirect "/foo", 301, "You are being redirected..."
  #   redirect to(MyController, :action, :id => 123)
  #   redirect to(:show_foo, :id => 123)

  def redirect uri, *args
    if @env[HTTP_VERSION] == 'HTTP/1.1' && @env[REQ_METHOD] != 'GET'
      status 303
    else
      status 302
    end

    @response[LOCATION] = url_to(uri.to_s)
    halt(*args)
  end


  ##
  # Halt execution of the current controller action and create a new request to
  # another action and/or controller, or path.
  #
  # Raises Gin::RouterError if the controller and action don't have a route.
  # Returns a 404 response if an unrecognized path is given.
  #
  # The rewrite method acts just as if a request had been sent from the client,
  # and will re-run any of the in-app middleware. If the app is itself running
  # as middleware, you may use rewrite to pass a request down to the next item
  # in the stack by specifying a path not supported by the app.
  #
  # Supports the same arguments at the Gin::Controller#url_to method.
  #
  #   rewrite MyController, :action
  #   #=> Calls app with route for MyController#action
  #
  #   rewrite MyController, :show, :id => 123
  #   #=> Calls app with route for MyController#action with the given params
  #
  #   rewrite :show_foo
  #   #=> Calls app with route for the current controller's :show_foo action,
  #   #=> or if missing the controller and action for the :show_foo named route.
  #
  #   # Rewrite and execute the request with the given headers.
  #   rewrite :show_foo, 'HTTP_X_CUSTOM_HEADER' => 'foo'
  #   rewrite :show_foo, params, 'HTTP_X_CUSTOM_HEADER' => 'foo'
  #
  #   # Rewrite to an arbitrary path.
  #   rewrite '/path/to/something/else', {}, 'REQUEST_METHOD' => 'POST'
  #
  # Note that params are not forwarded with the rewrite call. The app
  # considers this to be a completely different request, which means all params
  # required must be passed explicitely.
  #
  # Streamed and IO request content is also ignored unless it is explicitely
  # assigned to the 'rack.input' (as a part of the headers argument).

  def rewrite *args
    args.unshift(self.class) if Symbol === args[0] &&
                                self.class.actions.include?(args[0])
    halt(*@app.rewrite!(@env, *args))
  end


  ##
  # Unlike Gin::Controller#rewrite, the reroute method forwards the current
  # request and params to the provided controller and/or action, or named route.
  # Halts further execution in the current action.
  # Raises RouterError if a given named route isn't found in the app's routes.
  #
  #   reroute MyController, :action
  #   #=> Executes MyController#action
  #
  #   reroute MyController, :show, :id => 123
  #   #=> Executes MyController#action with the given params merged to
  #   #=> the current params.
  #
  #   reroute :show_foo
  #   #=> Executes the current controller's :show_foo action, or if missing
  #   #=> the controller and action for the :show_foo named route.
  #
  #   # Reroute with the given headers.
  #   reroute :show_foo, {}, 'HTTP_X_CUSTOM_HEADER' => 'foo'

  def reroute *args
    args.unshift(self.class) if Symbol === args[0] &&
                                self.class.actions.include?(args[0])
    nheaders = args.pop if Hash === args.last && Hash === args[-2] && args[-2] != args[-1]
    nparams  = args.pop if Hash === args.last

    if Class === args[0]
      ctrl_klass, naction = args[0..1]
    else
      route = @app.router.route_to(*args)
      ctrl_klass, naction = route.target
    end

    nenv = @env.merge(nheaders || {})
    nenv[GIN_PATH_PARAMS] = {}
    ctrl = ctrl_klass.new(@app, nenv)

    ctrl.params.merge!(params)
    ctrl.params.merge!(nparams) if nparams

    halt(*ctrl.call_action(naction))
  end


  ##
  # Assigns a file to the response body and halts the execution of the action.
  # Produces a 404 response if no file is found.

  def send_file path, opts={}
    if opts[:type] || !@response[CNT_TYPE]
      content_type opts[:type] || File.extname(path),
                    :default => 'application/octet-stream'
    end

    disposition = opts[:disposition]
    filename    = opts[:filename]
    disposition = 'attachment'        if disposition.nil? && filename
    filename    = File.basename(path) if filename.nil?

    if disposition
      @response[CNT_DISPOSITION] =
        "%s; filename=\"%s\"" % [disposition, filename]
    end

    last_modified opts[:last_modified] || File.mtime(path).httpdate
    halt 200 if @request.head?

    @response[CNT_LENGTH] = File.size?(path).to_s
    halt 200, File.open(path, "rb")

  rescue Errno::ENOENT
    halt 404
  end


  ##
  # Set the last modified time of the resource (HTTP 'Last-Modified' header)
  # and halt if conditional GET matches. The +time+ argument is a Time,
  # DateTime, or other object that responds to +to_time+ or +httpdate+.

  def last_modified time
    return unless time

    time = if Integer === time
             Time.at(time)
           elsif time.respond_to?(:to_time)
             time.to_time
           elsif !time.is_a?(Time)
             Time.parse time.to_s
           else
             time
           end

    @response[LAST_MOD] = time.httpdate
    return if @env[IF_NONE_MATCH]

    if status == 200 && @env[IF_MOD_SINCE]
      # compare based on seconds since epoch
      since = Time.httpdate(@env[IF_MOD_SINCE]).to_i
      halt 304 if since >= time.to_i
    end

    if @env[IF_UNMOD_SINCE] &&
      ((200..299).include?(status) || status == 412)

      # compare based on seconds since epoch
      since = Time.httpdate(@env[IF_UNMOD_SINCE]).to_i
      halt 412 if since < time.to_i
    end
  rescue ArgumentError
  end


  ##
  # Specify response freshness policy for HTTP caches (Cache-Control header).
  # Any number of non-value directives (:public, :private, :no_cache,
  # :no_store, :must_revalidate, :proxy_revalidate) may be passed along with
  # a Hash of value directives (:max_age, :min_stale, :s_max_age).
  #
  #   cache_control :public, :must_revalidate, :max_age => 60
  #   #=> Cache-Control: public, must-revalidate, max-age=60

  def cache_control *values
    if Hash === values.last
      hash = values.pop
      hash.reject!{|k,v| v == false || v == true && values << k }
    else
      hash = {}
    end

    values.map! { |value| value.to_s.tr('_','-') }
    hash.each do |key, value|
      key = key.to_s.tr('_', '-')
      value = value.to_i if key == "max-age"
      values << [key, value].join('=')
    end

    @response[CACHE_CTRL] = values.join(', ') if values.any?
  end


  ##
  # Set the Expires header and Cache-Control/max-age directive. Amount
  # can be an integer number of seconds in the future or a Time object
  # indicating when the response should be considered "stale". The remaining
  # "values" arguments are passed to the #cache_control helper:
  #
  #   expires 500, :public, :must_revalidate
  #   => Cache-Control: public, must-revalidate, max-age=60
  #   => Expires: Mon, 08 Jun 2009 08:50:17 GMT

  def expires amount, *values
    values << {} unless Hash === values.last

    if Integer === amount
      time    = Time.now + amount.to_i
      max_age = amount
    else
      time    = String === amount ? Time.parse(amount) : amount
      max_age = time - Time.now
    end

    values.last.merge!(:max_age => max_age) unless values.last[:max_age]
    cache_control(*values)

    @response[EXPIRES] = time.httpdate
  end


  ##
  # Sets Cache-Control, Expires, and Pragma headers to tell the browser
  # not to cache the response.

  def expire_cache_control
    @response[PRAGMA] = 'no-cache'
    expires EPOCH, :no_cache, :no_store, :must_revalidate, :max_age => 0
  end


  ##
  # Returns the url to an asset, including predefined asset cdn hosts if set.

  def asset_url name
    url = File.join(@app.asset_host_for(name).to_s, name)
    url = [url, *@app.asset_version(url)].compact.join("?") if url !~ %r{^https?://}
    url
  end


  ##
  # Check if an asset exists.
  # Returns the full system path to the asset if found, otherwise nil.

  def asset path
    @app.asset path
  end


  ##
  # Value of the layout to use for rendering.
  # See also Gin::Controller.layout and Gin::App.layout.

  def layout
    self.class.layout || @app.layout
  end


  ##
  # Returns the path to where the template is expected to be.
  #   template_path :foo
  #   #=> "<views_dir>/foo"
  #
  #   template_path "sub/foo"
  #   #=> "<views_dir>/sub/foo"
  #
  #   template_path "sub/foo", :layout
  #   #=> "<layouts_dir>/sub/foo"
  #
  #   template_path "/other/foo"
  #   #=> "<root_dir>/other/foo"

  def template_path template, is_layout=false
    dir = if template.to_s[0] == ?/
            @app.root_dir
          elsif is_layout
            @app.layouts_dir
          else
            @app.views_dir
          end

    path = File.join(dir, template.to_s)
    path.gsub!('*', controller_name)
    File.expand_path(path)
  end


  ##
  # Render a template with the given view template.
  # Options supported:
  # :locals:: Hash - local variables used in template
  # :layout:: Symbol/String - a custom layout to use
  # :scope:: Object - The scope in which to render the template: default self
  # :content_type:: Symbol/String - Content-Type header to set
  # :engine:: String - Tilt rendering engine to use
  # :layout_engine:: String - Tilt layout rendering engine to use
  #
  # The template argument may be a String or a Symbol. By default the
  # template location will be looked for under Gin::App.views_dir, but
  # the directory may be specified as any directory under Gin::App.root_dir
  # by using the '/' prefix:
  #
  #   view 'foo/template'
  #   #=> Renders file "<views_dir>/foo/template"
  #
  #   view '/foo/template'
  #   #=> Renders file "<root_dir>/foo/template"
  #
  #   # Render without layout
  #   view 'foo/template', layout: false

  def view template, opts={}, &block
    content_type(opts.delete(:content_type)) if opts[:content_type]

    scope  = opts[:scope]  || self
    locals = opts[:locals] || {}

    template   = template_path(template)
    v_template = @app.template_for template, opts[:engine]
    raise Gin::TemplateMissing, "No such template `#{template}'" unless v_template

    if opts[:layout] != false
      r_layout   = template_path((opts[:layout] || layout), true)
      r_template = @app.template_for r_layout, opts[:layout_engine] if r_layout
    end

    if !@response[CNT_TYPE]
      mime_type = v_template.class.default_mime_type ||
        r_template && r_template.class.default_mime_type
      content_type(mime_type) if mime_type
    end

    @env[GIN_TEMPLATES] ||= []

    if r_template
      @env[GIN_TEMPLATES] << r_template.file << v_template.file
      r_template.render(scope, locals){
        v_template.render(scope, locals, &block) }
    else
      @env[GIN_TEMPLATES] << v_template.file
      v_template.render(scope, locals, &block)
    end
  end


  ##
  # Taken from Sinatra.
  #
  # Run the block with 'throw :halt' support and apply result to the response.

  def invoke
    res = catch(:halt) { yield }
    res = [res] if Fixnum === res || String === res
    if Array === res && Fixnum === res.first
      res = res.dup
      status(res.shift)
      body(res.pop)
      headers(*res)
    elsif res.respond_to? :each
      body res
    end
    nil # avoid double setting the same response tuple twice
  end


  ##
  # Dispatch the call to the action, calling before and after filers, and
  # including error handling.

  def dispatch action
    @action = action

    invoke do
      filter(*before_filters_for(action))
      args = action_arguments action
      __send__(action, *args)
    end

  rescue => err
    invoke{ handle_error err }
  ensure
    filter(*after_filters_for(action))
  end


  ##
  # In development mode, returns an HTML page displaying the full error
  # and backtrace, otherwise shows a generic error page.
  #
  # Production error pages are first looked for in the public directory as
  # <status>.html or 500.html. If none is found, falls back on Gin's internal
  # error html pages.

  def html_error_page err, code=nil
    if @app.development?
      backtrace = err.backtrace || ['No backtrace :(']
      fulltrace = backtrace.join("\n")
      fulltrace = "<pre>#{h(fulltrace)}</pre>"

      apptrace  = Gin.app_trace(backtrace).join("\n")
      apptrace  = "<pre>#{h(apptrace)}</pre>" unless apptrace.empty?

      DEV_ERROR_HTML %
        [h(err.class), h(err.class), h(err.message), apptrace, fulltrace]

    else
      code ||= status
      filepath = asset("#{code}.html") || asset("500.html")

      unless filepath
        filepath = File.join(Gin::PUBLIC_DIR, "#{code}.html")
        filepath = File.join(Gin::PUBLIC_DIR, "500.html") if !File.file?(filepath)
      end

      File.open(filepath, "rb")
    end
  end


  ##
  # HTML-escape the given String.

  def h obj
    CGI.escapeHTML obj.to_s
  end


  private


  DEV_ERROR_HTML = File.read(File.join(Gin::PUBLIC_DIR, "error.html")).freeze #:nodoc:

  BAD_REQ_MSG = "Expected param `%s'" #:nodoc:

  ##
  # Get action arguments from the params.
  # Raises Gin::BadRequest if a required argument has no matching param.

  def action_arguments action=@action
    raise Gin::NotFound, "No action #{self.class}##{action}" unless
      self.class.actions.include? action.to_sym

    args = []
    temp = []
    prev_type = nil

    method(action).parameters.each do |(type, name)|
      val = params[name.to_s]

      raise Gin::BadRequest, BAD_REQ_MSG % name if type == :req && !val
      break if type == :rest || type == :block || name.nil?

      if type == :key
        # Ruby 2.0 hash keys arguments
        args.concat temp
        args << {} if prev_type != :key
        args.last[name] = val unless val.nil?

      elsif val.nil?
        temp << val

      else
        args.concat temp
        temp.clear
        args << val
      end

      prev_type = type
    end

    args
  end
end
