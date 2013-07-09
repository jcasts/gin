require 'test/test_helper'
require 'gin/test'

require 'plist'
require 'bson'
require 'nokogiri'
require 'json'


class TestTest < Test::Unit::TestCase

  def setup
    @testclass = Class.new MockTestClass
    @testclass.class_eval{
      include MockApp::TestHelper
      include TestAccess
    }
    @tests = @testclass.new
  end


  def test_included
    assert(@testclass < Gin::Test::Assertions)
    assert(@testclass < Gin::Test::Helpers)
    assert_equal MockApp, @testclass.app_klass
  end


  def test_controller
    assert_nil @testclass.controller
    @testclass.controller BarController
    assert_equal BarController, @testclass.controller
    assert_equal BarController, @tests.default_controller

    @tests.default_controller FooController
    assert_equal FooController, @tests.default_controller
    assert_equal BarController, @testclass.controller
  end


  def test_instance_init
    assert(MockApp === @tests.app)
    assert_nil @tests.controller
    assert_equal({'rack.input' => ""}, @tests.env)
    assert_equal([nil,{},[]], @tests.rack_response)
    assert_nil @tests.request
    assert_nil @tests.response
    assert_equal [], @tests.stream
    assert_equal "", @tests.body
    assert_nil @tests.default_controller
  end


  def test_path_to
    assert_nil @tests.default_controller
    assert_equal "/bar/123", @tests.path_to(:show_bar, id: 123)
    assert_equal "/bar/123", @tests.path_to(BarController, :show, id: 123)
    assert_equal "/bar?id=123", @tests.path_to("/bar", id: 123)
  end


  def test_path_to_default_ctrl
    @tests.default_controller BarController
    assert_equal "/bar/123", @tests.path_to(:show_bar, id: 123)
    assert_equal "/bar/123", @tests.path_to(:show, id: 123)
  end


  def test_path_to_no_ctrl
    assert_nil @tests.default_controller
    assert_raises(Gin::Router::PathArgumentError) do
      @tests.path_to(:show, id: 123)
    end
  end


  def test_make_request
    resp = @tests.make_request :get, :show_bar,
              {id: 123, foo: "BAR", bar: "BAZ"},'REMOTE_ADDR' => '127.0.0.1'

    assert_equal "foo=BAR&bar=BAZ", @tests.req_env['QUERY_STRING']
    assert_equal "/bar/123", @tests.req_env['PATH_INFO']
    assert_equal "127.0.0.1", @tests.req_env['REMOTE_ADDR']
    assert_equal "127.0.0.1", @tests.request.ip
    assert_equal "GET", @tests.req_env['REQUEST_METHOD']

    assert_equal Gin::Request, @tests.request.class
    assert_equal Gin::Response, @tests.response.class

    assert_equal resp, @tests.rack_response
    assert_equal 200, resp[0]
    assert_equal "text/html;charset=UTF-8", resp[1]["Content-Type"]
    assert_equal "9", resp[1]["Content-Length"]
    assert_equal ["SHOW 123!"], resp[2]

    assert_equal "SHOW 123!", @tests.body
    assert_equal ["SHOW 123!"], @tests.stream
    assert_equal [], @tests.templates

    assert BarController === @tests.controller
  end


  def test_make_request_w_views
    resp = @tests.make_request :get, :index_foo

    assert_equal "text/html;charset=UTF-8", resp[1]["Content-Type"]
    assert /Value is LOCAL/ === @tests.body

    assert_equal 2, @tests.templates.length
    assert_equal File.join(MockApp.layouts_dir, "foo.erb"), @tests.templates[0]
    assert_equal File.join(MockApp.views_dir, "bar.erb"), @tests.templates[1]
  end


  def test_make_request_w_cookies
    resp = @tests.make_request :get, :login_foo
    assert_equal "foo_session=12345; expires=Fri, 01 Jan 2100 00:00:00 -0000",
                 resp[1]["Set-Cookie"]

    time = Time.parse "2100-01-01 00:00:00 UTC"
    cookie = {name: "foo_session", value: "12345", expires_at: time}
    assert_equal cookie, @tests.cookies["foo_session"]

    @tests.set_cookie "bar", 5678
    resp = @tests.make_request :get, :show_bar, id: 123
    assert_equal "foo_session=12345; bar=5678", @tests.req_env['HTTP_COOKIE']
  end


  def test_cookie_parser
    @tests.make_request :get, :login_foo
    @tests.make_request :get, :supercookie_foo

    assert_equal 2, @tests.cookies.length

    time = Time.parse "2100-01-01 00:00:00 UTC"

    expected = {name: "foo_session", value: "12345", expires_at: time}
    assert_equal expected, @tests.cookies['foo_session']

    expected = {name: "supercookie", value: "SUPER!", domain: "mockapp.com",
      path: "/", expires_at: time, secure: true, http_only: true}
    assert_equal expected, @tests.cookies['supercookie']
  end


  def test_make_request_verb_methods
    %w{get post put patch delete head options}.each do |verb|
      resp = @tests.send verb, :show_bar, id: 123
      assert_equal verb.upcase, @tests.req_env['REQUEST_METHOD']
      if verb == 'get'
        assert_equal BarController,
                     @tests.req_env[Gin::Constants::GIN_CTRL].class
        assert_equal 200, resp[0]
      else
        assert_equal nil, @tests.req_env[Gin::Constants::GIN_CTRL]
        assert_equal 404, resp[0]
      end
    end
  end


  def test_parsed_body_json
    @tests.get '/api/json'
    assert_equal({'foo' => 1234}, @tests.parsed_body)
  end


  def test_parsed_body_bson
    @tests.get '/api/bson'
    assert_equal({'foo' => 1234}, @tests.parsed_body)
  end


  def test_parsed_body_plist
    @tests.get '/api/plist'
    assert_equal({'foo' => 1234}, @tests.parsed_body)
  end


  def test_parsed_body_xml
    @tests.get '/api/xml'
    assert_equal "foo", @tests.parsed_body.children.first.name
    assert_equal "1234", @tests.parsed_body.children.first.text
  end


  def test_parsed_body_html
    @tests.get '/foo'
    assert_equal "html", @tests.parsed_body.children.first.name
  end


  def test_parsed_body_missing_parser
    @tests.get '/api/pdf'
    assert_raises(RuntimeError) do
      @tests.parsed_body
    end
  end


  def test_assert_response_success
    assert_equal 0, @tests.assertions

    (200..299).each do |status|
      @tests.rack_response[0] = status
      assert @tests.assert_response(:success)
    end

    assert_equal 100, @tests.assertions
    assert_nil @tests.last_message

    @tests.rack_response[0] = 500
    assert_raises(MockAssertionError) do
      @tests.assert_response(:success)
    end

    assert_equal "Status expected to be in range 200..299 but was 500",
                  @tests.last_message
  end


  def test_assert_response_redirect
    assert_equal 0, @tests.assertions

    (301..303).each do |status|
      @tests.rack_response[0] = status
      assert @tests.assert_response(:redirect)
    end

    assert_equal 3, @tests.assertions
    assert_nil @tests.last_message

    @tests.rack_response[0] = 500
    assert_raises(MockAssertionError) do
      @tests.assert_response(:redirect)
    end

    assert_equal "Status expected to be in range 301..303 but was 500",
                  @tests.last_message
  end


  def test_assert_response_error
    assert_equal 0, @tests.assertions

    (500..599).each do |status|
      @tests.rack_response[0] = status
      assert @tests.assert_response(:error)
    end

    assert_equal 100, @tests.assertions
    assert_nil @tests.last_message

    @tests.rack_response[0] = 200
    assert_raises(MockAssertionError) do
      @tests.assert_response(:error)
    end

    assert_equal "Status expected to be in range 500..599 but was 200",
                  @tests.last_message
  end


  def test_assert_response_unauthorized
    assert_equal 0, @tests.assertions

    @tests.rack_response[0] = 401
    assert @tests.assert_response(:unauthorized)

    @tests.rack_response[0] = 500
    assert_raises(MockAssertionError) do
      @tests.assert_response(:unauthorized)
    end

    assert_equal "Status expected to be 401 but was 500", @tests.last_message
  end


  def test_assert_response_forbidden
    assert_equal 0, @tests.assertions

    @tests.rack_response[0] = 403
    assert @tests.assert_response(:forbidden)

    @tests.rack_response[0] = 500
    assert_raises(MockAssertionError) do
      @tests.assert_response(:forbidden)
    end

    assert_equal "Status expected to be 403 but was 500", @tests.last_message
  end


  def test_assert_response_not_found
    assert_equal 0, @tests.assertions

    @tests.rack_response[0] = 404
    assert @tests.assert_response(:not_found)

    @tests.rack_response[0] = 500
    assert_raises(MockAssertionError) do
      @tests.assert_response(:not_found)
    end

    assert_equal "Status expected to be 404 but was 500", @tests.last_message
  end


  def test_assert_response_other
    assert_equal 0, @tests.assertions

    @tests.rack_response[0] = 451
    assert @tests.assert_response(451)

    @tests.rack_response[0] = 500
    assert_raises(MockAssertionError) do
      @tests.assert_response(451)
    end

    assert_equal "Status expected to be 451 but was 500", @tests.last_message
  end


  def test_assert_data_json
    @tests.rack_response[1]['Content-Type'] = 'application/json'
    @tests.rack_response[2] =
      [{name:"bob",addresses:[{street:"123 bob st"},{street:"321 foo st"}]}.to_json]

    assert @tests.assert_data("name=bob")
    assert @tests.assert_data("name", value: "bob", count: 1)
    assert @tests.assert_data("addresses/*/street", count: 2)
  end


  def test_assert_data_bson
    @tests.rack_response[1]['Content-Type'] = 'application/bson'
    @tests.rack_response[2] =
      [BSON.serialize({name:"bob",addresses:[{street:"123 bob st"},{street:"321 foo st"}]}).to_s]

    assert @tests.assert_data("name=bob")
    assert @tests.assert_data("name", value: "bob", count: 1)
    assert @tests.assert_data("addresses/*/street", count: 2)
  end


  def test_assert_data_plist
    @tests.rack_response[1]['Content-Type'] = 'application/plist'
    @tests.rack_response[2] =
      [{name:"bob",addresses:[{street:"123 bob st"},{street:"321 foo st"}]}.to_plist]

    assert @tests.assert_data("name=bob")
    assert @tests.assert_data("name", value: "bob", count: 1)
    assert @tests.assert_data("addresses/*/street", count: 2)
  end


  def test_assert_xpath
    data = Nokogiri::XML::Builder.new do
      root{
        name "bob"
        address{ street "123 bob st" }
        address{ street "321 foo st" }
      }
    end.to_xml

    @tests.rack_response[1]['Content-Type'] = 'application/xml'
    @tests.rack_response[2] = [data]

    assert @tests.assert_xpath("/root/name", value: "bob", count: 1)
    assert @tests.assert_xpath(".//street", count: 2)
  end


  def test_assert_css
    html = <<-HTML
<!DOCTYPE html>
<html>
  <body>
    <h1 class="name">bob</h1>
    <div class="address"><div class="street">123 bob st</div></div>
    <div class="address"><div class="street">321 foo st</div></div>
  </body>
</html>
    HTML

    @tests.rack_response[1]['Content-Type'] = 'application/html'
    @tests.rack_response[2] = [html]

    assert @tests.assert_css(".name", value: "bob", count: 1)
    assert @tests.assert_css(".address>.street", count: 2)
  end


  def test_assert_select_invalid
    @tests.rack_response[1]['Content-Type'] = 'application/json'
    @tests.rack_response[2] = ['{"foo":123}']
    assert_raises(RuntimeError) do
      @tests.assert_select(".name", selector: :foo)
    end
  end


  def test_assert_select_failure
    @tests.rack_response[1]['Content-Type'] = 'application/json'
    @tests.rack_response[2] = ['{"foo":123}']

    assert_raises(MockAssertionError) do
      @tests.assert_select "/name"
    end
    assert_equal "Expected at least one item matching '/name' but found none",
                  @tests.last_message

    assert_raises(MockAssertionError) do
      @tests.assert_select "/foo", count: 2
    end
    assert_equal "Expected 2 items matching '/foo' but found 1",
                  @tests.last_message

    assert_raises(MockAssertionError) do
      @tests.assert_select "/foo", value: 321
    end

    assert_equal "Expected at least one item matching '/foo' with value 321 but found none",
                  @tests.last_message
  end


  def test_assert_cookie
    @tests.get :supercookie_foo

    assert @tests.assert_cookie("supercookie")
    assert @tests.assert_cookie("supercookie", value: "SUPER!")
    assert @tests.assert_cookie("supercookie", domain: "mockapp.com")

    attribs = {domain: "mockapp.com", value: "SUPER!", path: "/", secure: true,
      http_only: true, expires_at: Time.parse("Fri, 01 Jan 2100 00:00:00 -0000")}
    assert @tests.assert_cookie("supercookie", attribs)
  end


  def test_assert_cookie_failure_old_cookie
    @tests.get :login_foo
    @tests.get :supercookie_foo

    assert_raises(MockAssertionError) do
      @tests.assert_cookie "foo_session"
    end
    assert_equal "Expected cookie \"foo_session\" but it doesn't exist",
                 @tests.last_message
  end


  def test_assert_cookie_failure_bool_attr
    @tests.get :supercookie_foo

    [:secure, :http_only].each do |attr|
      assert_raises(MockAssertionError) do
        @tests.assert_cookie "supercookie", attr => false
      end
      assert_equal "Expected cookie #{attr} to be false but was true",
                   @tests.last_message
    end
  end


  def test_assert_cookie_failure_value
    @tests.get :supercookie_foo

    assert_raises(MockAssertionError) do
      @tests.assert_cookie "supercookie", value: "BLAH"
    end
    assert_equal "Expected cookie value to be \"BLAH\" but was \"SUPER!\"",
                 @tests.last_message
  end


  def test_assert_cookie_failure_other_attr
    @tests.get :supercookie_foo
    cookie = @tests.response_cookies["supercookie"]

    [:domain, :expires_at, :path].each do |attr|
      assert_raises(MockAssertionError) do
        @tests.assert_cookie "supercookie", attr => "BLAH"
      end
      assert_equal "Expected cookie #{attr} to be \"BLAH\" but was #{cookie[attr].inspect}",
                   @tests.last_message
    end
  end


  def test_assert_view
    @tests.get :index_foo
    assert @tests.assert_view("bar")
    assert @tests.assert_view("bar.erb")
  end


  def test_assert_view_failure
    @tests.get :index_foo
    assert_raises(MockAssertionError) do
      @tests.assert_view("bar.md")
    end
    assert_equal "Expected view `#{@tests.controller.template_path("bar.md")}' \
in:\n #{@tests.templates.join("\n ")}", @tests.last_message

    assert_raises(MockAssertionError) do
      @tests.assert_view("views/bar.erb")
    end
    assert_equal "Expected view `#{@tests.controller.template_path("views/bar.erb")}' \
in:\n #{@tests.templates.join("\n ")}", @tests.last_message
  end


  def test_assert_layout
    @tests.get :index_foo
    assert @tests.assert_layout("foo")
    assert @tests.assert_layout("foo.erb")
  end


  def test_assert_layout_failure
    @tests.get :index_foo
    assert_raises(MockAssertionError) do
      @tests.assert_layout("bar")
    end
    assert_equal "Expected layout `#{@tests.controller.template_path("bar", true)}' \
in:\n #{@tests.templates.join("\n ")}", @tests.last_message

    assert_raises(MockAssertionError) do
      @tests.assert_layout("layouts/foo.erb")
    end
    assert_equal "Expected layout `#{@tests.controller.template_path("layouts/foo.erb", true)}' \
in:\n #{@tests.templates.join("\n ")}", @tests.last_message
  end



  class MockAssertionError < StandardError; end

  module ::Gin::Test::Assertions
    module MiniTest
      Assertion = MockAssertionError unless const_defined?(:Assertion)
    end

    def raise err, msg=nil
      err, msg = RuntimeError, err if String === err && msg.nil?
      @last_message = err.respond_to?(:message) ? err.message : msg
      super
    end
  end


  class MockTestClass
    attr_reader :last_message, :assertions

    def initialize
      @assertions = 0
      @last_message = nil
    end

    def assert value, msg=nil
      @assertions += 1
      if value
        return true
      else
        msg ||= "Mock assertion failure message"
        @last_message = msg
        raise MockAssertionError, msg unless value
      end
    end
  end


  module TestAccess
    def env
      @req_env = super
    end

    def req_env
      @req_env
    end
  end


  class BarController < Gin::Controller
    controller_name "bar"

    def show id
      "SHOW #{id}!"
    end

    def index
      raise "OH NOES"
    end
  end


  class ApiController < Gin::Controller
    controller_name "api"

    def pdf
      content_type 'application/pdf'
      'fake pdf'
    end

    def json
      content_type :json
      '{"foo":1234}'
    end

    def bson
      content_type 'application/bson'
      BSON.serialize({'foo' => 1234}).to_s
    end

    def xml
      content_type :xml
      '<foo>1234</foo>'
    end

    def plist
      content_type 'application/plist'
      <<-STR
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">
<dict>\n\t<key>foo</key>\n\t<integer>1234</integer>\n</dict>\n</plist>
      STR
    end
  end


  class FooController < Gin::Controller
    controller_name "foo"
    layout "foo"

    def index
      view :bar, locals: {test_val: "LOCAL"}
    end

    def login
      set_cookie "foo_session", "12345",
        expires: Time.parse("Fri, 01 Jan 2100 00:00:00 -0000")
      "OK"
    end

    def supercookie
      set_cookie "supercookie", "SUPER!",
        expires:  Time.parse("Fri, 01 Jan 2100 00:00:00 -0000"),
        domain:   "mockapp.com",
        path:     "/",
        secure:   true,
        httponly: true
      "OK"
    end
  end


  class MockApp < Gin::App
    logger StringIO.new
    root_dir "test/app"

    mount BarController do
      get :show, "/:id"
      get :index, "/"
    end

    mount FooController

    mount ApiController
  end
end
