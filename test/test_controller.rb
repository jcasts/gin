require "test/test_helper"

unless defined? EventMachine
  class EventMachine; end
end

class AppController < Gin::Controller
  FILTERS_RUN = []

  before_filter :f1 do
    FILTERS_RUN << :f1
  end

  after_filter :f2 do
    FILTERS_RUN << :f2
  end

  error Gin::BadRequest do
    body "Bad Request"
  end
end

class BarController < AppController
  before_filter :stop, :only => :delete do
    FILTERS_RUN << :stop
    halt 404, "Not Found"
  end

  error 404 do
    content_type "text/plain"
    body "This is not the page you are looking for."
  end

  def show id
    "SHOW #{id}!"
  end

  def delete id, email=nil, name=nil
    "DELETE!"
  end

  def index
    raise "OH NOES"
  end

  def caught_error
    raise Gin::BadRequest, "Something is wrong"
  end
end


class ControllerTest < Test::Unit::TestCase
  class MockApp < Gin::App
    mount BarController do
      get :show, "/:id"
      get :delete, :rm_bar
      get :index, "/"
      get :caught_error
    end
  end


  def setup
    MockApp.instance_variable_set("@asset_host", nil)
    @app  = MockApp.new
    @ctrl = BarController.new(@app, rack_env)
  end


  def teardown
    BarController::FILTERS_RUN.clear
  end


  def rack_env
    @rack_env ||= {
      'HTTP_HOST' => 'example.com',
      'rack.input' => '',
      'gin.path_query_hash' => {'id' => 123},
    }
  end


  def test_set_cookie
    cookie = {:value => "user@example.com", :expires => Time.now + 360}
    @ctrl.cookies['test'] = cookie
    assert_equal cookie, @ctrl.env["rack.request.cookie_hash"]["test"]
    assert_equal "user@example.com", @ctrl.cookies['test'][:value]
  end


  def test_set_session
    @ctrl.session['test'] = 'user@example.com'
    assert_equal({"test"=>"user@example.com"}, @ctrl.env['rack.session'])
  end


  def test_call_action
    resp = @ctrl.call_action(:show)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal [200, {"Content-Type"=>"text/html", "Content-Length"=>"9"},
      ["SHOW 123!"]], resp
  end


  def test_call_action_error
    assert_raises(RuntimeError){ @ctrl.call_action(:index) }
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
  end


  def test_call_action_caught_error
    resp = @ctrl.call_action(:caught_error)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal [400, {"Content-Type"=>"text/html", "Content-Length"=>"11"},
      ["Bad Request"]], resp
  end


  def test_call_action_halt
    resp = @ctrl.call_action(:delete)
    assert_equal [:f1, :stop, :f2], BarController::FILTERS_RUN
    assert_equal [404, {"Content-Type"=>"text/plain", "Content-Length"=>"41"},
      ["This is not the page you are looking for."]], resp
  end


  def test_dispatch
    @ctrl.send(:dispatch, :show)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal 200, @ctrl.response.status
    assert_equal ["SHOW 123!"], @ctrl.response.body
  end


  def test_dispatch_error
    assert_raises(RuntimeError){ @ctrl.send(:dispatch, :index) }
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal 500, @ctrl.response.status
    assert RuntimeError === @ctrl.env['gin.errors'].first
    assert_equal [], @ctrl.response.body
  end


  def test_dispatch_filter_halt
    @ctrl.send(:dispatch, :delete)
    assert_equal [:f1, :stop, :f2], BarController::FILTERS_RUN
    assert_equal 404, @ctrl.response.status
    assert_equal ["Not Found"], @ctrl.response.body
  end


  def test_invoke
    @ctrl.send(:invoke){ "test body" }
    assert_equal ["test body"], @ctrl.body

    @ctrl.send(:invoke){ [401, "test body"] }
    assert_equal 401, @ctrl.status
    assert_equal ["test body"], @ctrl.body

    @ctrl.send(:invoke){ [302, {'Location' => 'http://foo.com'}, "test body"] }
    assert_equal 302, @ctrl.status
    assert_equal 'http://foo.com', @ctrl.response['Location']
    assert_equal ["test body"], @ctrl.body

    @ctrl.send(:invoke){ 301 }
    assert_equal 301, @ctrl.status
  end


  def test_action_arguments
    assert_raises(NameError){ @ctrl.send("action_arguments", "nonaction") }
    assert_equal [], @ctrl.send("action_arguments", "index")

    assert_equal [123], @ctrl.send("action_arguments", "show")
    assert_equal [123, nil, nil], @ctrl.send("action_arguments", "delete")

    @ctrl.params.update 'name' => 'bob'
    assert_equal [123,nil,'bob'], @ctrl.send("action_arguments", "delete")

    @ctrl.params.delete('id')
    assert_raises(Gin::BadRequest){
      @ctrl.send("action_arguments", "show")
    }
  end


  def test_asset_path
    assert_equal "/foo.jpg", @ctrl.asset_path("foo.jpg")

    MockApp.asset_host "http://example.com"
    assert_equal "http://example.com/foo.jpg", @ctrl.asset_path("foo.jpg")

    MockApp.asset_host do |file|
      file =~ /\.js$/ ? "http://js.example.com" : "http://img.example.com"
    end
    assert_equal "http://js.example.com/foo.js",   @ctrl.asset_path("foo.js")
    assert_equal "http://img.example.com/foo.jpg", @ctrl.asset_path("foo.jpg")
  end


  def test_redirect_non_get
    rack_env['REQUEST_METHOD'] = 'POST'
    rack_env['HTTP_VERSION']   = 'HTTP/1.0'
    catch(:halt){ @ctrl.redirect "/foo" }
    assert_equal 302, @ctrl.status
    assert_equal "http://example.com/foo", @ctrl.response['Location']

    rack_env['HTTP_VERSION'] = 'HTTP/1.1'
    catch(:halt){ @ctrl.redirect "/foo" }
    assert_equal 303, @ctrl.status
    assert_equal "http://example.com/foo", @ctrl.response['Location']
  end


  def test_redirect
    catch(:halt){ @ctrl.redirect "/foo" }
    assert_equal 302, @ctrl.status
    assert_equal "http://example.com/foo", @ctrl.response['Location']

    resp = catch(:halt){ @ctrl.redirect "https://google.com/foo", 301, "Move Along" }
    assert_equal 302, @ctrl.status
    assert_equal "https://google.com/foo", @ctrl.response['Location']
    assert_equal [301, "Move Along"], resp

    resp = catch(:halt){ @ctrl.redirect "https://google.com/foo", 301, {'X-LOC' => "test"}, "Move Along" }
    assert_equal 302, @ctrl.status
    assert_equal "https://google.com/foo", @ctrl.response['Location']
    assert_equal [301, {'X-LOC' => "test"}, "Move Along"], resp
  end


  def test_url_to
    assert_equal "http://example.com/bar/123",
                  @ctrl.url_to(BarController, :show, :id => 123)
    assert_equal "http://example.com/bar/123", @ctrl.url_to(:show, :id => 123)
    assert_equal "http://example.com/bar/delete?id=123",
                  @ctrl.url_to(:rm_bar, :id => 123)
    assert_equal "https://foo.com/path?id=123",
                  @ctrl.url_to("https://foo.com/path", :id => 123)
    assert_equal "http://example.com/bar/123",
                  @ctrl.to(BarController, :show, :id => 123)
  end


  def test_path_to
    assert_equal "/bar/123", @ctrl.path_to(BarController, :show, id: 123)
    assert_equal "/bar/123", @ctrl.path_to(:show, id: 123)
    assert_equal "/bar/delete?id=123", @ctrl.path_to(:rm_bar, id: 123)
    assert_equal "/bar/delete", @ctrl.path_to(:rm_bar)
    assert_equal "/test?id=123", @ctrl.path_to("/test", id: 123)
    assert_equal "/test", @ctrl.path_to("/test")
  end


  def test_session
    assert_equal(@ctrl.request.session, @ctrl.session)
  end


  def test_params
    assert_equal({'id' => 123}, @ctrl.params)
    assert_equal(@ctrl.request.params, @ctrl.params)
  end


  def test_logger
    assert_equal @app.logger, @ctrl.logger
  end


  def test_stream
    @ctrl.stream{|out| out << "BODY"}
    assert Gin::Stream === @ctrl.body
    assert_equal Gin::Stream, @ctrl.body.instance_variable_get("@scheduler")

    @ctrl.env.merge! "async.callback" => lambda{}

    @ctrl.stream{|out| out << "BODY"}
    assert Gin::Stream === @ctrl.body
    assert_equal EventMachine, @ctrl.body.instance_variable_get("@scheduler")
  end


  def test_headers
    @ctrl.headers "Content-Length" => 123
    assert_equal @ctrl.response.headers, @ctrl.headers
    assert_equal({"Content-Length"=>123}, @ctrl.headers)
  end


  def test_error_num_and_str
    resp = catch :halt do
      @ctrl.error 404, "Not Found"
      "BAD RESP"
    end

    assert_equal 404, resp
    assert_equal ["Not Found"], @ctrl.body
  end


  def test_error_num
    resp = catch :halt do
      @ctrl.error 404
      "BAD RESP"
    end

    assert_equal 404, resp
    assert_equal [], @ctrl.body
  end


  def test_error_str
    resp = catch :halt do
      @ctrl.error "OH NOES"
      "BAD RESP"
    end

    assert_equal 500, resp
    assert_equal ["OH NOES"], @ctrl.body
  end


  def test_halt_single
    resp = catch :halt do
      @ctrl.halt 400
      "BAD RESP"
    end

    assert_equal 400, resp
  end


  def test_halt_ary
    resp = catch :halt do
      @ctrl.halt 201, "Accepted"
      "BAD RESP"
    end

    assert_equal [201, "Accepted"], resp
  end


  def test_content_type
    assert_nil @ctrl.content_type
    assert_nil @ctrl.response['Content-Type']

    @ctrl.content_type 'text/json'
    assert_equal 'text/json', @ctrl.content_type
    assert_equal 'text/json', @ctrl.response['Content-Type']
  end


  def test_body
    assert_equal [], @ctrl.body
    assert_equal [], @ctrl.response.body

    @ctrl.body("<HTML></HTML>")
    assert_equal ["<HTML></HTML>"], @ctrl.body
    assert_equal ["<HTML></HTML>"], @ctrl.response.body
  end


  def test_status
    assert_equal 200, @ctrl.status
    assert_equal 200, @ctrl.response.status

    @ctrl.status(404)
    assert_equal 404, @ctrl.status
    assert_equal 404, @ctrl.response.status
  end


  def test_init
    assert Gin::Request  === @ctrl.request
    assert Gin::Response === @ctrl.response
    assert_nil @ctrl.response['Content-Type']
    assert_equal @app, @ctrl.app
    assert_equal rack_env, @ctrl.env
  end


  def test_supports_features
    assert Gin::Controller.ancestors.include?(Gin::Filterable)
    assert Gin::Controller.ancestors.include?(Gin::Errorable)
  end


  def test_class_controller_name
    assert_equal "app", AppController.controller_name
    assert_equal "bar", BarController.controller_name

    assert_equal "app", AppController.new(nil,rack_env).controller_name
  end


  def test_class_content_type
    assert_equal "text/html", AppController.content_type
    assert_equal "text/html", BarController.content_type

    AppController.content_type "application/json"
    assert_equal "application/json", AppController.content_type
    assert_equal "application/json", BarController.content_type

    BarController.content_type "text/plain"
    assert_equal "application/json", AppController.content_type
    assert_equal "text/plain",       BarController.content_type

  ensure
    AppController.instance_variable_set("@content_type",nil)
    BarController.instance_variable_set("@content_type",nil)
  end
end
