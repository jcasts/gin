class Gin::App
  def self.TestHelper
    return @test_helper if defined?(@test_helper)
    @test_helper = Module.new
    @test_helper.send(:include, Gin::Test::Helpers)
    @test_helper.app_klass = self
    @test_helper
  end
end


module Gin::Test; end


##
# Helper assertion methods for tests.
# To contextualize tests to a specific app, use the
# automatically generated module assigned to your app's class:
#
#   class MyCtrlTest < Test::Unit::TestCase
#     include MyApp::TestHelper     # Sets App for mock requests.
#     controller MyHomeController   # Sets default controller to use.
#
#     def test_home
#       get :home
#       assert_response :success
#     end
#   end


module Gin::Test::Assertions

  def self.included subclass
    subclass.instance_eval do
      def correct_302_redirect
        @correct_302_redirect = true
      end
      def correct_302_redirect?
        @correct_302_redirect = false unless defined?(@correct_302_redirect)
        @correct_302_redirect
      end
    end
  end


  def correct_302_redirect?
    self.class.correct_302_redirect?
  end


  ##
  # Asserts the response status code and headers.
  # Takes an integer (status code) or Symbol as the expected value:
  #   :success::      2XX status codes
  #   :redirect::     301-303 status codes
  #   :forbidden::    403 status code
  #   :unauthorized:: 401 status code
  #   :not_found::    404 status code

  def assert_response expected, headers={}, msg=nil
    status = @rack_response[0]
    case expected
    when :success
      assert [200..299].include?(status),
        msg || "Status expected to be in range 200..299 but was #{status}"
    when :redirect
      assert [301..303].include?(status),
        msg || "Status expected to be in range 301..303 but was #{status}"
    when :unauthorized
      assert_equal 401, status,
        msg || "Status expected to be 401 but was #{status}"
    when :forbidden
      assert_equal 403, status,
        msg || "Status expected to be 403 but was #{status}"
    when :not_found
      assert_equal 404, status,
        msg || "Status expected to be 404 but was #{status}"
    when :error
      assert [500..599].include?(status),
        msg || "Status expected to be in range 500..599 but was #{status}"
    else
      assert_equal expected, status,
        msg || "Status expected to be #{expected} but was #{status}"
    end
  end


  ##
  # Checks for data points in the response body.
  # Looks at the response Content-Type to parse.
  # Supports JSON, BSON, XML, PLIST, and HTML.
  #
  # If value is a Class, Range, or Regex, does a match.
  # Options supported are:
  # :attributes:: Hash - Key/Value pairs of data node attributes.
  # :count:: Integer - Number of occurences of the data point.

  def assert_body key_or_path, value=nil, opts={}, msg=nil
    ct = @rack_response[1]['Content-Type']

    case ct
    when /[/+]json$/i
      require 'json'
      

    when /[/+]bson$/i
      require 'bson'
      

    when /[/+]plist/i
      require 'plist'
      

    when /[/+]xml/i
      require 'nokogiri'
      

    when /[/+]html/i
      require 'nokogiri'
      

    else
      raise "No parser available for content-type #{ct}"
    end
  end


  ##
  # Checks that the given Cookie is set with the expected values.
  # Options supported:
  # :secure::     Boolean - SSL cookies only
  # :http_only::  Boolean - HTTP only cookie
  # :domain::     String  - Domain on which the cookie is used
  # :expires::    Time    - Date and time of cookie expiration
  # :path::       String  - Path cookie applies to

  def assert_cookie name, value=nil, opts={}, msg=nil
    
  end


  ##
  # Checks that the rendered template name or path matches the one given.

  def assert_template name_or_path, msg=nil
    # TODO: IMPLEMENT RENDERING WITH TILT
  end


  ##
  # Checks that the response is a redirect to a given url or controller+action.

  def assert_redirected_to url_or_ctrl, exp_action=nil, msg=nil
    msg, exp_action = exp_action, nil if
      String === url_or_ctrl && String === exp_action

    assert_response :redirect

    if Class === url_or_ctrl && url_or_ctrl < Gin::Controller
      verb = if correct_302_redirect? && @rack_response[0] == 302
              @env['REQUEST_METHOD']
             else
              'GET'
             end
      ctrl, action, = @app.router.resources_for(verb, path)
      expected = "#{url_or_ctrl}##{exp_action}"
      real     = "#{ctrl}##{action}"

      assert_equal expected, real,
        msg || "Expected redirect to #{expected} but got #{real}"

    else
      real = @rack_response[1]['Location']
      assert_equal url_or_ctrl, real,
        msg || "Expected redirect to #{url_or_ctrl} but got #{real}"
    end
  end


  ##
  # Checks that the given route is valid and points to the expected
  # controller and action.

  def assert_route verb, path, exp_ctrl, exp_action, msg=nil
    ctrl, action, = @app.router.resources_for(verb, path)
    expected = "#{exp_ctrl}##{exp_action}"
    real     = "#{ctrl}##{action}"

    assert_equal expected, real,
      msg || "Route should map to #{expected} but got #{real}"
  end
end


##
# Helper methods for tests. To contextualize tests to a specific app, use the
# automatically generated module assigned to your app's class:
#
#   class MyCtrlTest < Test::Unit::TestCase
#     include MyApp::TestHelper     # Sets App for mock requests.
#     controller MyHomeController   # Sets default controller to use.
#
#     def test_home
#       get :home
#       assert_response :success
#     end
#   end

module Gin::Test::Helpers

  include Gin::Test::Assertions

  def self.included subclass
    subclass.instance_eval do
      class << self
        attr_accessor :app_klass
      end

      ##
      # Sets the default controller to use when making requests
      # for all tests in the given class.
      #   class MyCtrlTest < Test::Unit::TestCase
      #     include MyApp::TestHelper
      #     controller MyCtrl
      #   end

      def controller ctrl_klass=nil
        @default_controller = ctrl_klass if ctrl_klass
        @default_controller
      end
    end
  end


  ##
  # The App instance being used for the requests.

  def app
    @app ||= self.class.app_klass.new
  end


  ##
  # The Rack env for the next mock request.

  def env
    @env ||= {'rack.input' => ""}
  end


  ##
  # The standard Rack response array.

  def rack_response
    @rack_response ||= [nil,{},[]]
  end


  ##
  # The Gin::Controller instance used by the last mock request.

  def controller
    @controller
  end


  ##
  # The Gin::Request instance on the controller used by the last mock request.

  def request
    controller && controller.request
  end

  ##
  # The Gin::Response instance on the controller used by the last mock request.

  def response
    controller && controller.response
  end


  ##
  # Make a GET request.
  #   get FooController, :show, :id => 123
  #
  #   # With default_controller set to FooController
  #   get :show, :id => 123
  #
  #   # Default named route
  #   get :show_foo, :id => 123
  #
  #   # Request with headers
  #   get :show_foo, {:id => 123}, 'Cookie' => 'value'
  #   get :show_foo, {}, 'Cookie' => 'value'

  def get *args
    make_request :get, *args
  end


  ##
  # Make a POST request. See 'get' method for usage.

  def post *args
    make_request :post, *args
  end


  ##
  # Make a PUT request. See 'get' method for usage.

  def put *args
    make_request :put, *args
  end


  ##
  # Make a PATCH request. See 'get' method for usage.

  def patch *args
    make_request :patch, *args
  end


  ##
  # Make a DELETE request. See 'get' method for usage.

  def delete *args
    make_request :delete, *args
  end


  ##
  # Make a HEAD request. See 'get' method for usage.

  def head *args
    make_request :head, *args
  end


  ##
  # Make a OPTIONS request. See 'get' method for usage.

  def options *args
    make_request :options, *args
  end


  ##
  # Make a mock request to the given http verb and path,
  # controller+action, or named route.
  #
  #   make_request :get, FooController, :show, :id => 123
  #
  #   # With default_controller set to FooController
  #   make_request :get, :show, :id => 123
  #
  #   # Default named route
  #   make_request :get, :show_foo, :id => 123
  #
  #   # Request with headers
  #   make_request :get, :show_foo, {:id => 123}, 'Cookie' => 'value'
  #   make_request :get, :show_foo, {}, 'Cookie' => 'value'

  def make_request verb, *args
    headers = (Hash === args[-2] && Hash === args[-1]) ? args.pop : {}
    path, query = path_to(*args).split("?")

    env['REQUEST_METHOD'] = verb.to_s.upcase
    env['QUERY_STRING']   = query
    env['PATH_INFO']      = path
    env.merge! headers

    @rack_response = app.call(env)
    @controller    = @env[GIN_CTRL]
    @env = nil
    @rack_response
  end


  ##
  # Sets a cookie for the next mock request.
  #   set_cookie "mycookie", "FOO", :expires => 600, :path => "/"
  #   set_cookie "mycookie", :expires => 600

  def set_cookie name, value, opts={}
    if Hash === value
      opts = value
    else
      opts[:value] = value
    end

    
  end


  ##
  # Cookies assigned to the response.

  def cookies
    
  end


  ##
  # Sets the default controller to use when making requests for the
  # duration of a test case.

  def default_controller ctrl_klass=nil
    @default_controller = ctrl_klass if ctrl_klass
    @default_controller || self.class.controller
  end


  ##
  # Build a path to the given controller and action or route name,
  # with any expected params. If no controller is specified and the default
  # controller responds to the symbol given, uses the default controller for
  # path lookup.
  #
  #   path_to FooController, :show, :id => 123
  #   #=> "/foo/123"
  #
  #   # With default_controller set to FooController
  #   path_to :show, :id => 123
  #   #=> "/foo/123"
  #
  #   # Default named route
  #   path_to :show_foo, :id => 123
  #   #=> "/foo/123"

  def path_to *args
    return "#{args[0]}#{"?" << Gin.build_query(args[1]) if args[1]}" if String === args[0]

    args.unshift(@default_controller) if
      Symbol === args[0] && @default_controller.actions.include?(args[0])

    @app.router.path_to(*args)
  end
end
