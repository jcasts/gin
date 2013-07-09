require 'test/test_helper'
require 'gin/test'

class TestTest < Test::Unit::TestCase

  def setup
    @testclass = Class.new MockTestClass
    @testclass.class_eval{
      include MockApp.TestHelper
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
    assert_equal "GET", @tests.req_env['REQUEST_METHOD']

    assert_equal resp, @tests.rack_response
    assert_equal 200, resp[0]
    assert_equal "text/html;charset=UTF-8", resp[1]["Content-Type"]
    assert_equal "9", resp[1]["Content-Length"]
    assert_equal ["SHOW 123!"], resp[2]
  end


  def test_make_request_w_cookies
  end


  def test_make_request_w_headers
  end


  def test_make_request_verb_methods
  end


  def test_parsed_body
  end


  def test_parsed_body_missing_parser
  end


  def test_cookie_get_and_set
  end


  class MockTestClass; end

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


  class FooController < Gin::Controller
  end


  class MockApp < Gin::App
    logger StringIO.new

    mount BarController do
      get :show, "/:id"
      get :index, "/"
    end
  end
end
