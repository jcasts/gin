class Gin::Controller
  extend GinClass
  include Gin::Filterable
  include Gin::Errorable

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

  attr_reader :app, :request, :response, :action


  def initialize app, env
    @app      = app
    @action   = nil
    @request  = Gin::Request.new env
    @response = Gin::Response.new
    @response['Content-Type'] = self.class.content_type
  end


  def call_action action #:nodoc:
    invoke{ dispatch action }
    invoke{ handle_status(@response.status) }
    content_type 'text/html' unless @response['Content-Type']
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

  def body bdy=nil
    @response.body = bdy if bdy
    @response.body
  end


  ##
  # Get or set the HTTP response Content-Type header.

  def content_type ct=nil
    @response['Content-Type'] = ct if ct
    @response['Content-Type']
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
    code, body     = 500, code.to_str if code.respond_to? :to_str
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
  # Send a 301, 302, or 303 redirect.

  def redirect uri, *args
    
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
  # Build a path to the given controller and action, with any expected params.

  def path_to controller, action, params={}
    @app.router.path_to controller, action, params
  end


  ##
  # Returns the full path to an asset

  def asset_path type, name
    
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


  def dispatch action #:nodoc:
    @action = action
    invoke do
      __call_filters__ before_filters, action
      __send__ action
    end

  rescue => err
    invoke{ handle_error err }
  ensure
    __call_filters__ after_filters, action
  end
end
