require "test/test_helper"

class FooController < Gin::Controller;
  def index; end
  def create; end
end

class FooApp < Gin::App
  mount FooController do
    get  :index,  "/"
    post :create, "/"
  end
end

class MissingRouteApp < Gin::App
  mount FooController do
    get :index, "/"
  end
end

class ExtraRouteApp < Gin::App
  mount FooController do
    get  :index,  "/"
    post :create, "/"
    post :delete, "/delete"
  end
end

class FooMiddleware
  @@called = false
  attr_reader :app, :args
  def initialize app, *args
    @app  = app
    @args = args
    @@called = false
  end

  def self.reset!
    @@called = false
  end

  def self.called?
    @@called
  end

  def call env
    @@called = true
    @app.call env
  end
end


class AppTest < Test::Unit::TestCase

  def setup
    FooApp.instance_variable_set("@environment", nil)
    FooApp.instance_variable_set("@asset_host", nil)
    FooApp.instance_variable_set("@middleware", nil)
    @app  = FooApp.new Logger.new($stdout)
    @rapp = FooApp.new lambda{|env| [200,{'Content-Type'=>'text/html'},["HI"]]}
  end


  def teardown
    ENV.delete 'RACK_ENV'
  end


  def test_use_middleware
    FooApp.use FooMiddleware, :foo, :bar
    assert_equal [FooMiddleware, :foo, :bar], FooApp.middleware[0]
    assert !FooMiddleware.called?

    myapp = FooApp.new
    myapp.call({'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'})
    assert FooMiddleware.called?

    FooMiddleware.reset!
    myapp.call!({'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'})
    assert !FooMiddleware.called?
  end


  def test_mime_type
    assert_equal "foo/blah", Gin::App.mime_type("foo/blah")
    assert_equal "text/html", Gin::App.mime_type(:html)
    assert_equal "application/json", Gin::App.mime_type(:json)
    assert_equal "text/plain", Gin::App.mime_type(".txt")

    assert_equal Gin::App.mime_type(:json), @app.mime_type(:json)
  end


  def test_set_mime_type
    assert_nil Gin::App.mime_type(:foo)
    Gin::App.mime_type(:foo, "application/foo")
    assert_equal "application/foo", @app.mime_type(:foo)
  end


  def test_asset_host_for
    FooApp.asset_host do |name|
      "http://#{File.extname(name)[1..-1] << "." if name}foo.com"
    end
    assert_equal "http://js.foo.com", FooApp.asset_host_for("app.js")
    assert_equal "http://js.foo.com", @app.asset_host_for("app.js")
  end


  def test_asset_host
    FooApp.asset_host "http://example.com"
    assert_equal "http://example.com", FooApp.asset_host
    assert_equal "http://example.com", @app.asset_host

    FooApp.asset_host{ "https://foo.com" }
    assert_equal "https://foo.com", FooApp.asset_host
    assert_equal "https://foo.com", @app.asset_host
  end


  def test_default_dirs
    assert_equal File.expand_path("..",__FILE__), FooApp.root_dir
    assert_equal File.expand_path("../public",__FILE__), FooApp.public_dir
    assert_equal File.expand_path("..",__FILE__), @app.root_dir
    assert_equal File.expand_path("../public",__FILE__), @app.public_dir
  end


  def test_init
    assert Logger === @app.logger, "logger attribute should be a Logger"
    assert Logger === @rapp.logger, "logger attribute should be a Logger"
    assert_nil @app.rack_app, "Rack application should be nil by default"
    assert Proc === @rapp.rack_app, "Rack application should be a Proc"
    assert Gin::Router === @app.router, "Should have a Gin::Router"
    assert @app.router.resources_for("get", "/foo"),
      "App should route GET /foo"
  end


  def test_init_missing_routes
    assert_raises Gin::App::RouterError do
      MissingRouteApp.new
    end
  end


  def test_init_extra_routes
    assert_raises Gin::App::RouterError do
      ExtraRouteApp.new
    end
  end


  def test_generic_http_response
    resp = @app.generic_http_response 404, "Not Found", "OH NOES"
    assert_equal 3, resp.length
    assert_equal 404, resp[0]
    assert_equal "text/html", resp[1]['Content-Type']
    assert resp[2][0].include?("<title>Not Found</title>"), "HTML title missing"
    assert resp[2][0].include?("<h1>Not Found</h1>"), "Page title missing"
    assert resp[2][0].include?("<p>OH NOES</p>"), "Message should be present"
  end


  def test_default_environment
    assert FooApp.development?
    assert !FooApp.test?
    assert !FooApp.staging?
    assert !FooApp.production?
  end


  def test_default_inst_environment
    assert @app.development?
    assert !@app.test?
    assert !@app.staging?
    assert !@app.production?
  end


  def test_environment
    ENV['RACK_ENV'] = 'production'
    assert !FooApp.development?
    assert !FooApp.test?
    assert !FooApp.staging?
    assert FooApp.production?
  end


  def test_inst_environment
    ENV['RACK_ENV'] = 'production'
    assert !@app.development?
    assert !@app.test?
    assert !@app.staging?
    assert @app.production?
  end


  def test_set_environment
    %w{development test staging production}.each do |name|
      FooApp.environment name
      mname = name + "?"
      assert @app.send(mname), "Instance environment should be #{name}"
      assert FooApp.send(mname), "Class environment should be #{name}"
    end
  end
end
