class Gin::Controller
  extend GinClass
  include Gin::Filterable
  include Gin::Errorable

  ##
  # Array of action names for this controller.

  def self.actions
    instance_methods(false)
  end


  ##
  # String representing the controller name.
  # Underscores the class name and removes mentions of 'controller'.
  #   MyApp::FooController.controller_name
  #   #=> "my_app/foo"

  def self.controller_name
    @ctrl_name ||= self.to_s.underscore.gsub(/_?controller_?/,'')
  end


  ##
  # Set or get the default content type for this Gin::Controller.
  # Default value is "text/html". This attribute is inherited.

  def self.content_type new_type=nil
    return @content_type = new_type if new_type
    return @content_type if @content_type
    self.superclass.respond_to?(:content_type) ?
      self.superclass.content_type.dup : "text/html"
  end


  class_proxy_reader :controller_name

  attr_reader :app, :request, :response, :action, :env


  def initialize app, env
    @app      = app
    @action   = nil
    @env      = env
    @request  = Gin::Request.new env
    @response = Gin::Response.new
    @response[Gin::Response::H_CTYPE] = self.class.content_type
  end


  def call_action action #:nodoc:
    invoke{ dispatch action }
    invoke{ handle_status(@response.status) }
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
  # Get or set the HTTP response Content-Type header.

  def content_type ct=nil
    @response[Gin::Response::H_CTYPE] = ct if ct
    @response[Gin::Response::H_CTYPE]
  end


  ##
  # Stop the execution of an action and return the response.

  def halt *resp
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
  # Set multiple response headers with Hash.

  def headers hash=nil
    @response.headers.merge! hash if hash
    @response.headers
  end


  ##
  # Assigns a Gin::Stream to the response body, which is yielded to the block.
  # The block execution is delayed until the action returns.
  #   stream do |io|
  #     file = File.open "somefile", "r"
  #     io << file.read(1024) until file.eof?
  #     file.close
  #   end

  def stream keep_open=false, &block
    scheduler = env['async.callback'] ? EventMachine : Gin::Stream
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
  #   path_to :show_foo, :id => 123
  #   #=> "/foo/123"

  def path_to *args
    return "#{args[0]}#{"?" << args[1].to_query if args[1]}" if String === args[0]
    args.unshift(self.class) if Symbol === args[0] && respond_to?(args[0])
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
    host << "http#{'s' if request.secure?}://"

    if request.forwarded? or request.port != (request.secure? ? 443 : 80)
      host << request.host_with_port
    else
      host << request.host
    end

    uri << request.script_name.to_s
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
  #   redirect to(MyController, :action)
  #   redirect to(:show_foo)

  def redirect uri, *args
    if @env['HTTP_VERSION'] == 'HTTP/1.1' && @env["REQUEST_METHOD"] != 'GET'
      status 303
    else
      status 302
    end

    @response['Location'] = url_to(uri.to_s)
    halt(*args)
  end


  ##
  # Returns the full path to an asset, including predefined asset cdn hosts.

  def asset_path name
    File.join(@app.asset_host_for(name).to_s, name)
  end


  private


  ##
  # Taken from Sinatra.
  #
  # Run the block with 'throw :halt' support and apply result to the response.

  def invoke
    res = catch(:halt) { yield }
    res = [res] if Fixnum === res or String === res
    if Array === res and Fixnum === res.first
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
      __call_filters__ before_filters, action
      args = action_arguments action
      __send__(action, *args)
    end

  rescue => err
    invoke{ handle_error err }
  ensure
    __call_filters__ after_filters, action
  end


  BAD_REQ_MSG = "Expected param `%s'" #:nodoc:

  ##
  # Get action arguments from the params.
  # Raises Gin::BadRequest if a required argument has no matching param.

  def action_arguments action=@action
    m = method(action)

    args = []
    m.parameters.each do |(type, name)|
      raise Gin::BadRequest, BAD_REQ_MSG % name if
        type == :req && !params[name]
      args << params[name]
    end

    args
  end
end
