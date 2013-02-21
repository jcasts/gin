require "test/test_helper"

class AppTest < Test::Unit::TestCase

  class FooController < Gin::Controller;
    def index; end
    def create; end
  end

  class FooApp < Gin::App
    mount FooController do
      get :index,   "/"
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
      get :index, "/"
      post :create, "/"
      post :delete, "/delete"
    end
  end

  def setup
    FooApp.instance_variable_set("@environment", nil)
    @app  = FooApp.new Logger.new($stdout)
    @rapp = FooApp.new lambda{|env| [200,{'Content-Type'=>'text/html'},["HI"]]}
  end


  def teardown
    ENV.delete 'RACK_ENV'
  end


  def test_init
    assert Logger === @app.logger, "logger attribute should be a Logger"
    assert Logger === @rapp.logger, "logger attribute should be a Logger"
    assert_nil @app.rack_app, "Rack application should be nil by default"
    assert Proc === @rapp.rack_app, "Rack application should be a Proc"
    assert Gin::Router === @app.router, "Should have a Gin::Router"
    assert @app.router.resources_for("get", "/app_test/foo"),
      "App should route GET /app_test/foo"
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
      FooApp.environment = name
      mname = name + "?"
      assert @app.send(mname), "Instance environment should be #{name}"
      assert FooApp.send(mname), "Class environment should be #{name}"
    end
  end
end
