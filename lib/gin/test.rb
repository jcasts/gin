require 'time'


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
    status = rack_response[0]
    case expected
    when :success
      assert (200..299).include?(status),
        msg || "Status expected to be in range 200..299 but was #{status.inspect}"
    when :redirect
      assert (301..303).include?(status),
        msg || "Status expected to be in range 301..303 but was #{status.inspect}"
    when :unauthorized
      assert 401 == status,
        msg || "Status expected to be 401 but was #{status.inspect}"
    when :forbidden
      assert 403 == status,
        msg || "Status expected to be 403 but was #{status.inspect}"
    when :not_found
      assert 404 == status,
        msg || "Status expected to be 404 but was #{status.inspect}"
    when :error
      assert (500..599).include?(status),
        msg || "Status expected to be in range 500..599 but was #{status.inspect}"
    else
      assert expected == status,
        msg || "Status expected to be #{expected.inspect} but was #{status.inspect}"
    end
  end


  ##
  # Checks for data points in the response body.
  # Looks at the response Content-Type to parse.
  # Supports JSON, BSON, XML, PLIST, and HTML.
  #
  # If value is a Class, Range, or Regex, does a match.
  # Options supported are:
  # :count:: Integer - Number of occurences of the data point.
  #
  # If body is parsed with Nokogiri, first argument must be
  # xpath, otherwise a Ruby-Path format.
  #
  #   # With XPath
  #   assert_data './/address[@domestic=Yes]'
  #
  #   # With ruby-path
  #   assert_data '**/address/domestic=YES/../value'

  def assert_data key_or_path, value=nil, opts={}, msg=nil
    data = parsed_body
    val_msg = " with value #{value.inspect}" if !value.nil?
    count = 0

    case data
    when Array, Hash
      use_lib 'path', 'ruby-path'
      data.find_data(key_or_path) do |p,k,pa|
        count += 1 if value.nil? || value === p[k]
        break unless opts[:count]
      end

    when Nokogiri::XML::Document, Nokogiri::HTML::Document
      data.each do |node|
        count += 1 if value.nil? || value === node.text
        break unless opts[:count]
      end

    else
      raise "Can't use data type #{data.class}"
    end

    if opts[:count]
      assert opts[:count] == count,
        msg || "Expected #{opts[:count]} items matching '#{key_or_path}'#{val_msg} but found #{count}"
    else
      assert((count > 0),
        msg || "Expected at least one item matching '#{key_or_path}'#{val_msg} but found none")
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
    opts ||= {}
    opts[:value] = value
    cookie = cookies[name]

    opts.each do |k,v|
      next if v == cookie[k]
      err_msg = msg || "Expected cookie #{k} to be #{v.inspect} but was #{cookie[k].inspect}"

      raise Minitest::Assertion, err_msg.to_s
    end

    assert cookie, msg || "Expected cookie #{name} but it doesn't exist"
  end


  ##
  # Checks that a rendered view name or path matches the one given.

  def assert_view view, msg=nil
    @templates ||= []
    expected = @app.template_files(@controller.template_path(view)).first
    assert @templates.include?(expected),
      msg || "Expected view `#{name_or_path}' in #{@templates.inspect}"
  end


  ##
  # Checks that a specific layout was use to render the response.

  def assert_layout layout, msg=nil
    @templates ||= []
    expected = @app.template_files(@controller.template_path(layout, true)).first
    assert @templates.include?(expected),
      msg || "Expected view `#{name_or_path}' in #{@templates.inspect}"
  end


  ##
  # Checks that the response is a redirect to a given url or controller+action.

  def assert_redirected_to url_or_ctrl, exp_action=nil, msg=nil
    msg, exp_action = exp_action, nil if
      String === url_or_ctrl && String === exp_action

    if Class === url_or_ctrl && url_or_ctrl < Gin::Controller
      verb = if correct_302_redirect? && rack_response[0] == 302
              @env['REQUEST_METHOD']
             else
              'GET'
             end

      ctrl, action, = @app.router.resources_for(verb, path)
      expected = "#{url_or_ctrl}##{exp_action}"
      real     = "#{ctrl}##{action}"

      errmsg = msg || "Expected redirect to #{expected.inspect} but got #{real.inspect}"
      raise Minitest::Assertion, errmsg unless expected == real

    else
      real = rack_response[1]['Location']
      errmsg = msg || "Expected redirect to #{url_or_ctrl.inspect} but got #{real.inspect}"
      raise Minitest::Assertion, errmsg unless url_or_ctrl == real
    end

    assert_response :redirect
  end


  ##
  # Checks that the given route is valid and points to the expected
  # controller and action.

  def assert_route verb, path, exp_ctrl, exp_action, msg=nil
    ctrl, action, = @app.router.resources_for(verb, path)
    expected = "#{exp_ctrl}##{exp_action}"
    real     = "#{ctrl}##{action}"

    assert expected == real,
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
#
# All requests are full stack, meaning any in-app middleware will be run as
# a part of a request. The goal is to test controllers in the context of the
# whole app, and easily do integration-level tests as well.

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


  def use_lib lib, gemname=nil # :nodoc:
    require lib
  rescue LoadError => e
    raise unless e.message == "cannot load such file -- #{lib}"
    gemname ||= lib
    puts "You need the `#{gemname}' gem to access some of the features you are \
trying to use.
Run the following command and try again: gem install #{gemname}"
    exit 1
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

    env['HTTP_COOKIE'] =
      @set_cookies.map{|k,v| "#{k}=#{v}"}.join("; ") if @set_cookies

    env['REQUEST_METHOD'] = verb.to_s.upcase
    env['QUERY_STRING']   = query
    env['PATH_INFO']      = path
    env.merge! headers

    @rack_response = app.call(env)
    @controller    = env[GIN_CTRL]
    @templates     = env[GIN_TEMPLATES]

    @env         = nil
    @body        = nil
    @parsed_body = nil
    @set_cookies = nil

    cookies.each{|n, c| set_cookie(n, c[:value]) }

    @rack_response
  end


  ##
  # Sets a cookie for the next mock request.
  #   set_cookie "mycookie", "FOO"

  def set_cookie name, value
    @set_cookies ||= {}
    @set_cookies[name] = value
  end


  COOKIE_MATCH = /\A([^(),\/<>@;:\\\"\[\]?={}\s]+)(?:=([^;]*))?\Z/ # :nodoc:

  ##
  # Cookies assigned to the response. Will not show expired cookies,
  # but cookies will otherwise persist across multiple requests in the
  # same test case.
  #   cookies['session']
  #   #=> {:value => "foo", :expires => <#Time>}

  def cookies
    return @cookies if @cookies || !rack_response

    tmp_cookies = {}

    Array(rack_response[1]['Set-Cookie']).each do |set_cookie_value|
      args = { }
      params=set_cookie_value.split(/;\s*/)

      first=true
      params.each do |param|
        result = COOKIE_MATCH.match param
        if !result
          raise "Invalid cookie parameter in cookie '#{set_cookie_value}'"
        end

        key = result[1].downcase.to_sym
        keyvalue = result[2]
        if first
          args[:name] = result[1]
          args[:value] = keyvalue
          first = false
        else
          case key
          when :expires
            begin
              args[:expires_at] = Time.parse keyvalue
            rescue ArgumentError
              raise unless $!.message == "time out of range"
              args[:expires_at] = Time.at(0x7FFFFFFF)
            end
          when *[:domain, :path]
            args[key] = keyvalue
          when :secure
            args[:secure] = true
          when :httponly
            args[:http_only] = true
          else
            raise "Unknown cookie parameter '#{key}'"
          end
        end
      end

      tmp_cookies[args[:name]] = args
    end

    @cookies = tmp_cookies
  end


  ##
  # The read String body of the response.

  def body
    return @body if @body
    @body = ""
    rack_response[2].each{|str| @body << str }
    @body
  end


  ##
  # The data representing the parsed String body
  # of the response, according to the Content-Type.
  #
  # Supports JSON, BSON, XML, PLIST, and HTML.
  # Returns plain Ruby objects for JSON, BSON, and PLIST.
  # Returns a Nokogiri document object for XML and HTML.

  def parsed_body
    return @parsed_body if @parsed_body
    ct = rack_response[1]['Content-Type']

    @parsed_body =
      case ct
      when /[\/+]json$/i
        use_lib 'json'
        JSON.parse(body)

      when /[\/+]bson$/i
        use_lib 'bson'
        BSON.deserialize(body)

      when /[\/+]plist/i
        use_lib 'plist'
        Plist.parse_xml(body)

      when /[\/+]xml/i
        use_lib 'nokogiri'
        Nokogiri::XML(body)

      when /[\/+]html/i
        use_lib 'nokogiri'
        Nokogiri::HTML(body)

      else
        raise "No parser available for content-type #{ct}"
      end
  end


  ##
  # The body stream as returned by the Rack response Array.
  # Responds to #each.

  def stream
    rack_response[2]
  end


  ##
  # Sets the default controller to use when making requests.
  # Best used in a test setup context.
  #
  #   def setup
  #     default_controller HomeController
  #   end

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
