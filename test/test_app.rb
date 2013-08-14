require "test/test_helper"
require "stringio"

class FooController < Gin::Controller;
  def index; "FOO"; end
  def create; end
  def show id; "FOO ID = #{id}"; end
  def error; raise "Something bad happened"; end
end

class BadErrDelegate < Gin::Controller
  error{ raise "Bad error handler, bad!" }
end

class ErrDelegate < Gin::Controller
  error{|err| body err.message }
end


class FooApp < Gin::App
  mount FooController do
    get  :index,  "/"
    post :create, "/"
    get  :error,  "/error"
    get  :show, "/:id"
  end

  def reloaded?
    @reloaded ||= false
  end

  def reload!
    @reloaded = true
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
  include Gin::Constants

  class NamespacedApp < Gin::App; end

  FOO_ROUTER = FooApp.router

  def setup
    FooApp.setup
    FooApp.options[:router] = FOO_ROUTER

    @error_io = StringIO.new
    FooApp.logger(@error_io)

    @app  = FooApp.new
    @rapp = FooApp.new lambda{|env| [200,{'Content-Type'=>'text/html'},["HI"]]}
  end


  def teardown
    ENV.delete 'RACK_ENV'
  end


  def test_class_proxies
    proxies = [:protection, :sessions, :session_secret, :middleware,
      :error_delegate, :router, :root_dir, :public_dir, :environment,
      :mime_type, :asset_host, :options, :config, :autoreload, :md5s,
      :templates]

    proxies.each do |name|
      assert FooApp.respond_to?(name), "Gin::App should respond to #{name}"
      assert @app.respond_to?(name), "Gin::App instance should respond to #{name}"
    end
  end


  def test_class_call
    assert_nil FooApp.instance_variable_get("@instance")

    env  = {'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'}
    resp = FooApp.call env
    assert_equal 200, resp[0]
    assert_equal "3", resp[1]['Content-Length']
    assert_equal ["FOO"],  resp[2]

    assert FooApp === FooApp.instance_variable_get("@instance")
    app = FooApp.instance_variable_get("@instance")

    FooApp.call env
    assert_equal app, FooApp.instance_variable_get("@instance")
  end


  def test_namespace
    assert_nil FooApp.namespace
    assert_equal self.class, NamespacedApp.namespace
  end


  def test_protection
    assert_equal false, FooApp.protection

    FooApp.protection(test: "thing")
    assert_equal({test:"thing"}, FooApp.protection)

    FooApp.protection false
    assert_equal false, FooApp.protection
  end


  def test_autoreload
    FooApp.setup
    FooApp.environment "production"
    @app = FooApp.new
    assert_equal false, FooApp.autoreload
    assert_equal false, @app.autoreload

    FooApp.autoreload true
    @app = FooApp.new
    assert_equal true, FooApp.autoreload
    assert_equal true, @app.autoreload

    FooApp.autoreload false
    @app = FooApp.new
    assert_equal false, FooApp.autoreload
    assert_equal false, @app.autoreload
  end


  def test_autoreload_dev
    FooApp.environment "development"
    @app = FooApp.new
    assert_equal true, FooApp.autoreload
    assert_equal true, @app.autoreload

    FooApp.autoreload false
    @app = FooApp.new
    assert_equal false, FooApp.autoreload
    assert_equal false, @app.autoreload
  end


  def test_sessions
    assert_equal false, FooApp.sessions

    FooApp.sessions(test: "thing")
    assert_equal({test:"thing"}, FooApp.sessions)

    FooApp.sessions false
    assert_equal false, FooApp.sessions
  end


  def test_session_secret
    assert_equal 64, FooApp.session_secret.length
    FooApp.session_secret "this is my secret!"
    assert_equal "this is my secret!", FooApp.session_secret
  end


  def test_source_class
    old_name = FooApp.instance_variable_get("@source_class")
    assert_equal FooApp, FooApp.source_class

    FooApp.instance_variable_set("@source_class", "MissingRouteApp")
    assert_equal MissingRouteApp, FooApp.source_class

  ensure
    FooApp.instance_variable_set("@source_class", old_name)
  end


  def test_config_dir
    assert_equal File.join(FooApp.root_dir, "config"), FooApp.config_dir
    assert_equal File.join(FooApp.root_dir, "config"), FooApp.config.dir
    assert_equal File.join(FooApp.root_dir, "config"), @app.config.dir

    FooApp.config_dir "/foo/blah"
    assert_equal "/foo/blah", FooApp.config_dir
    assert_equal "/foo/blah", FooApp.config.dir
    assert_equal "/foo/blah", @app.config.dir
  end


  def test_config_env
    assert_equal 'development', FooApp.environment
    assert_equal 'development', FooApp.config.environment
    assert_equal 'development', @app.config.environment

    FooApp.environment "production"
    assert_equal "production", FooApp.config.environment
    assert_equal "production", @app.config.environment
  end


  def test_config_reload
    assert_equal false, FooApp.config_reload
    assert_equal false, FooApp.config.ttl
    assert_equal false, @app.config.ttl

    FooApp.config_reload 300
    assert_equal 300, FooApp.config.ttl
    assert_equal 300, @app.config.ttl
  end


  def test_config_logger
    assert_equal @error_io, FooApp.logger
    assert_equal @error_io, FooApp.config.logger
    assert_equal @error_io, @app.config.logger

    FooApp.logger "mock_logger"
    assert_equal "mock_logger", FooApp.config.logger
    assert_equal "mock_logger", @app.config.logger
  end


  def test_config
    @app = FooApp.new
    assert Gin::Config === @app.config
    assert @app.config == FooApp.config
    assert @app.config.instance_variable_get("@data").empty?
  end


  def test_config_with_dir
    FooApp.setup
    FooApp.config_dir "./test/mock_config"
    @app = FooApp.new
    assert_equal 1, FooApp.config['backend.connections']
    assert_equal 1, @app.config['backend.connections']
  end


  def test_layout
    assert_equal :layout, FooApp.layout
    assert_equal :layout, @app.layout

    FooApp.layout "foo"
    assert_equal "foo", FooApp.layout
    assert_equal :layout, @app.layout

    @app = FooApp.new
    assert_equal "foo", @app.layout
  end


  def test_layouts_dir
    assert_equal File.join(FooApp.root_dir, "layouts"), FooApp.layouts_dir
    FooApp.root_dir "test/foo"
    assert_equal File.join(FooApp.root_dir, "layouts"), FooApp.layouts_dir
    assert_equal File.join(@app.root_dir, "layouts"), @app.layouts_dir
  end


  def test_views_dir
    assert_equal File.join(FooApp.root_dir, "views"), FooApp.views_dir
    FooApp.root_dir "test/foo"
    assert_equal File.join(FooApp.root_dir, "views"), FooApp.views_dir
    assert_equal File.join(@app.root_dir, "views"), @app.views_dir
  end


  def test_template_engines
    FooApp.setup
    default = Tilt.mappings.merge(nil => [Tilt::ERBTemplate])
    assert_equal default, FooApp.options[:template_engines]
    assert_equal default, @app.template_engines

    FooApp.default_template Tilt::ERBTemplate, "custom", "thing"

    assert_equal default, @app.template_engines
    @app = FooApp.new
    assert_equal [Tilt::ERBTemplate], @app.template_engines['custom']
    assert_equal [Tilt::ERBTemplate], @app.template_engines['thing']

    FooApp.default_template Tilt::HamlTemplate
    assert_equal [Tilt::HamlTemplate, Tilt::ERBTemplate],
      FooApp.options[:template_engines][nil]
  end


  def test_template_for
    FooApp.default_template Tilt::ERBTemplate, "erb"
    @app = FooApp.new root_dir: "./test/app"
    template = @app.template_for "./test/app/layouts/foo"

    assert Tilt::ERBTemplate === template
    assert_equal "./test/app/layouts/foo.erb", template.file
  end


  def test_template_for_invalid
    @app = FooApp.new root_dir: "./test/app"
    template = @app.template_for "./test/app/layouts/ugh"
    assert_nil template
  end


  def test_template_files
    @app = FooApp.new root_dir: "./test/app"

    files = @app.template_files "./test/app/layouts/foo"
    assert_equal ["./test/app/layouts/foo.erb"], files

    files = @app.template_files "./test/app/layouts/ugh"
    assert_equal [], files
  end


  def test_error_delegate
    assert_equal Gin::Controller, FooApp.error_delegate
    FooApp.error_delegate FooController
    assert_equal FooController, FooApp.error_delegate
  end


  def test_use_middleware
    FooApp.use FooMiddleware, :foo, :bar
    assert_equal [FooMiddleware, :foo, :bar], FooApp.middleware[0]
    assert !FooMiddleware.called?

    myapp = FooApp.new logger: @error_io
    myapp.call({'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'})
    assert FooMiddleware.called?

    FooMiddleware.reset!
    myapp.dispatch({'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'}, FooController, :index)
    assert !FooMiddleware.called?
  end


  def test_rewrite_env
    time = Time.now
    env = {'rack.input' => 'id=foo', 'PATH_INFO' => '/foobar', 'REQUEST_METHOD' => 'GET',
          'REMOTE_ADDR' => '127.0.0.1', GIN_RELOADED => true, GIN_TIMESTAMP => time,
          GIN_CTRL => FooController, GIN_ACTION => :index}

    expected_env = env.dup
    expected_env.delete(GIN_CTRL)
    expected_env.delete(GIN_ACTION)
    expected_env['REQUEST_METHOD'] = 'POST'
    expected_env['PATH_INFO'] = '/foo'
    expected_env['QUERY_STRING'] = nil

    assert_equal expected_env, @app.rewrite_env(env, FooController, :create)

    assert_raises Gin::RouterError do
      @app.rewrite_env(env, FooController, :bad_action)
    end

    assert_raises Gin::Router::PathArgumentError do
      @app.rewrite_env(env, FooController, :show)
    end

    expected_env['REQUEST_METHOD'] = 'GET'
    expected_env['PATH_INFO'] = '/foo/123'
    expected_env['QUERY_STRING'] = 'blah=456'

    assert_equal expected_env,
      @app.rewrite_env(env, FooController, :show, {:id => 123, :blah => 456}, 'REQUEST_METHOD' => 'POST')
  end


  def test_rewrite_env_custom_path
    time = Time.now
    env = {'rack.input' => 'id=foo', 'PATH_INFO' => '/foobar', 'REQUEST_METHOD' => 'GET',
          'REMOTE_ADDR' => '127.0.0.1', GIN_RELOADED => true, GIN_TIMESTAMP => time,
          GIN_CTRL => FooController, GIN_ACTION => :index}

    expected_env = env.dup
    expected_env.delete(GIN_CTRL)
    expected_env.delete(GIN_ACTION)
    expected_env['REQUEST_METHOD'] = 'POST'
    expected_env['PATH_INFO'] = '/foo'
    expected_env['QUERY_STRING'] = nil

    assert_equal expected_env, @app.rewrite_env(env, '/foo', {}, 'REQUEST_METHOD' => 'POST')
    assert_raises Gin::Router::PathArgumentError do
      @app.rewrite_env(env, '/foo/:id', {}, 'REQUEST_METHOD' => 'POST')
    end

    expected_env['PATH_INFO'] = '/foo/123'
    expected_env['QUERY_STRING'] = 'blah=456'

    assert_equal expected_env,
      @app.rewrite_env(env, '/foo/:id', {:id => 123, :blah => 456}, 'REQUEST_METHOD' => 'POST')
  end


  def test_rewrite
    env = {'rack.input' => 'id=foo', 'PATH_INFO' => '/foobar', 'REQUEST_METHOD' => 'GET',
          'REMOTE_ADDR' => '127.0.0.1'}

    resp = @app.rewrite!(env, FooController, :show, :id => 123)
    @app.logger.rewind

    assert_equal ["FOO ID = 123"], resp[2]
    assert_equal "[REWRITE] GET /foobar -> GET /foo/123\n", @app.logger.readline
  end


  def test_rewrite_path
    env = {'rack.input' => 'id=foo', 'PATH_INFO' => '/foobar', 'REQUEST_METHOD' => 'GET',
          'REMOTE_ADDR' => '127.0.0.1'}

    resp = @app.rewrite!(env, '/other/path/:id', {:id => 123}, 'REQUEST_METHOD' => 'PUT')
    @app.logger.rewind

    assert_equal 404, resp[0]
    assert_equal "[REWRITE] GET /foobar -> PUT /other/path/123\n", @app.logger.readline
  end


  def test_call_reload
    FooApp.autoreload true
    myapp = FooApp.new @error_io

    assert !myapp.reloaded?
    myapp.call 'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'

    assert myapp.reloaded?
  end


  def test_call_static
    resp = @app.call 'rack.input' => "",
                     'PATH_INFO' => '/gin.css',
                     'REQUEST_METHOD' => 'GET'

    assert_equal 200, resp[0]
    assert_equal File.read(@app.asset("gin.css")), resp[2].read
  end


  def test_call_rack_app
    env   = {'rack.input' => "", 'PATH_INFO' => '/bad', 'REQUEST_METHOD' => 'GET'}
    expected = [200, {'Content-Length'=>"5"}, "AHOY!"]
    myapp = lambda{|_| expected }
    @app = FooApp.new myapp

    resp = @app.call env
    assert_equal expected, resp
  end



  def test_call!
    resp = @app.call! 'rack.input' => "",
                      'PATH_INFO' => '/foo',
                      'REQUEST_METHOD' => 'GET'
    assert_equal 200, resp[0]
    assert_equal "3", resp[1]['Content-Length']
    assert_equal 'text/html;charset=UTF-8', resp[1]['Content-Type']
    assert_equal ["FOO"], resp[2]
  end


  def test_dispatch
    FooApp.environment 'test'
    env = {'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'}

    resp = @app.dispatch env, FooController, :index
    assert_equal 200, resp[0]
    assert_equal "3", resp[1]['Content-Length']
    assert_equal 'text/html;charset=UTF-8', resp[1]['Content-Type']
    assert_equal ["FOO"], resp[2]
  end


  def test_dispatch_not_found
    FooApp.environment 'test'
    @app = FooApp.new
    env = {'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'}

    resp = @app.dispatch env, FooController, :bad
    assert_equal 404, resp[0]
    assert_equal "288", resp[1]['Content-Length']
    assert_equal 'text/html;charset=UTF-8', resp[1]['Content-Type']
    assert_equal @app.asset("404.html"), resp[2].path
  end


  def test_dispatch_no_handler
    FooApp.environment 'test'
    @app = FooApp.new
    env = {'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'}

    resp = @app.dispatch env, FooController, nil
    assert_equal 404, resp[0]
    assert_equal "288", resp[1]['Content-Length']
    assert_equal 'text/html;charset=UTF-8', resp[1]['Content-Type']
    assert_equal @app.asset("404.html"), resp[2].path

    msg = "[ERROR] Gin::NotFound: No route exists for: GET /foo"
    @error_io.rewind
    assert @error_io.read.include?(msg)
  end


  def test_dispatch_error
    FooApp.environment 'test'
    @app = FooApp.new
    env  = {'rack.input' => "", 'PATH_INFO' => '/bad', 'REQUEST_METHOD' => 'GET'}
    resp = @app.dispatch env, FooController, :error

    assert_equal 500, resp[0]
    assert_equal @app.asset("500.html"), resp[2].path
    @error_io.rewind
    assert @error_io.read.include?("[ERROR] RuntimeError: Something bad happened\n")
  end


  def test_handle_error
    FooApp.error_delegate ErrDelegate
    @app = FooApp.new
    env = {'rack.input' => "", 'PATH_INFO' => '/bad', 'REQUEST_METHOD' => 'GET'}
    err = ArgumentError.new("Unexpected Argument")

    resp = @app.handle_error err, env

    assert_equal 500, resp[0]
    assert_equal ["Unexpected Argument"], resp[2]
    assert_equal({"Content-Type"=>"text/html;charset=UTF-8", "Content-Length"=>"19"}, resp[1])

    assert_equal err, env['gin.errors'].first
  end


  def test_handle_error_no_delegate
    FooApp.environment "production"
    @app = FooApp.new
    env = {'rack.input' => "", 'PATH_INFO' => '/bad', 'REQUEST_METHOD' => 'GET'}
    resp = @app.handle_error ArgumentError.new("Unexpected Argument"), env

    assert_equal 500, resp[0]
    assert_equal File.read(@app.asset("500.html")), resp[2].read
    assert_equal({"Content-Type"=>"text/html;charset=UTF-8", "Content-Length"=>"348"}, resp[1])
  end


  def test_handle_error_bad_delegate
    FooApp.environment "production"
    FooApp.error_delegate BadErrDelegate
    @app = FooApp.new

    env = {'rack.input' => "", 'PATH_INFO' => '/bad', 'REQUEST_METHOD' => 'GET'}
    err = ArgumentError.new("Unexpected Argument")

    resp = @app.handle_error ArgumentError.new("Unexpected Argument"), env
    assert_equal 500, resp[0]
    assert_equal File.read(@app.asset("500.html")), resp[2].read
    assert_equal({"Content-Type"=>"text/html;charset=UTF-8", "Content-Length"=>"348"}, resp[1])

    assert_equal err, env['gin.errors'].first
    assert RuntimeError === env['gin.errors'].last
  end


  def test_handle_error_gin_controller_issue
    env = {'rack.input' => "", 'PATH_INFO' => '/bad', 'REQUEST_METHOD' => 'GET'}
    err = ArgumentError.new("Unexpected Argument")
    old_handler = Gin::Controller.error_handlers[Exception]
    Gin::Controller.error_handlers[Exception] = lambda{|_| raise Gin::Error, "FRAMEWORK IST KAPUT"}

    assert_raises(Gin::Error){ @app.handle_error err, env }
  ensure
    Gin::Controller.error_handlers[Exception] = old_handler
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


  def test_asset_version
    old_dir = FooApp.public_dir
    FooApp.public_dir File.dirname(__FILE__)
    @app = FooApp.new

    md5_cmd = RUBY_PLATFORM =~ /darwin/ ? 'md5 -q' : 'md5sum'
    expected = `#{md5_cmd} #{__FILE__}`[0...8]

    assert_equal expected, @app.asset_version(File.basename(__FILE__))

  ensure
    FooApp.public_dir old_dir
  end


  def test_asset_host_for
    FooApp.asset_host do |name|
      "http://#{File.extname(name)[1..-1] << "." if name}foo.com"
    end
    @app = FooApp.new
    assert_equal "http://js.foo.com", @app.asset_host_for("app.js")
  end


  def test_asset_host
    FooApp.asset_host "http://example.com"
    @app = FooApp.new
    assert_equal "http://example.com", FooApp.asset_host
    assert_equal "http://example.com", @app.asset_host

    FooApp.asset_host{ "https://foo.com" }
    @app = FooApp.new
    assert_equal Proc, FooApp.asset_host.class
    assert_equal "https://foo.com", @app.asset_host
  end


  def test_asset
    FooApp.public_dir "./test/mock_config"
    @app = FooApp.new
    assert @app.asset("backend.yml") =~ %r{/gin/test/mock_config/backend\.yml$}
    assert @app.asset("500.html") =~ %r{/gin/public/500\.html$}

    assert !@app.asset("foo/../../mock_config/backend.yml")
    assert !@app.asset("foo/../../public/500.html")
  end


  def test_bad_asset
    FooApp.public_dir "./test/mock_config"
    @app = FooApp.new
    assert_nil @app.asset("bad_file")
    assert_nil @app.asset("../../History.rdoc")

    path = File.join(FooApp.public_dir, "../.././test/mock_config/../../History.rdoc")
    assert File.file?(path)
    assert_nil @app.asset("../.././test/mock_config/../../History.rdoc")
  end


  def test_static_no_file
    env = {'rack.input' => "", 'PATH_INFO' => '/foo', 'REQUEST_METHOD' => 'GET'}
    assert !@app.static!(env)
  end


  def test_static
    env = {'rack.input' => "", 'REQUEST_METHOD' => 'GET'}
    env['PATH_INFO'] = '/500.html'
    assert @app.static!(env)
    assert env['gin.static'] =~ %r{/gin/public/500\.html$}
  end


  def test_static_updir
    env = {'rack.input' => "", 'REQUEST_METHOD' => 'GET'}
    env['PATH_INFO'] = '../../gin/public/500.html'
    assert !@app.static!(env)
    assert !env['gin.static']
  end


  def test_static_head
    env = {'rack.input' => "", 'REQUEST_METHOD' => 'GET'}
    env['REQUEST_METHOD'] = 'HEAD'
    env['PATH_INFO'] = '/500.html'
    assert @app.static!(env)
    assert env['gin.static'] =~ %r{/gin/public/500\.html$}
  end


  def test_non_static_verbs
    env = {'rack.input' => "", 'REQUEST_METHOD' => 'GET'}
    env['PATH_INFO'] = '/backend.yml'

    FooApp.public_dir "./test/mock_config"
    @app = FooApp.new
    assert @app.static!(env)
    assert env['gin.static'] =~ %r{/gin/test/mock_config/backend\.yml$}

    %w{POST PUT DELETE TRACE OPTIONS}.each do |verb|
      env['REQUEST_METHOD'] = verb
      assert !@app.static!(env), "#{verb} should not be a static request"
    end
  end


  def test_default_dirs
    assert_equal File.expand_path("..",__FILE__), FooApp.root_dir
    assert_equal File.expand_path("../public",__FILE__), FooApp.public_dir
    assert_equal File.expand_path("..",__FILE__), @app.root_dir
    assert_equal File.expand_path("../public",__FILE__), @app.public_dir
  end


  def test_init
    @app = FooApp.new
    assert_equal @error_io, @app.logger, "logger should default to class logger"
    assert_equal @error_io, @rapp.logger, "logger should default to class logger"
    assert_nil @app.rack_app, "Rack application should be nil by default"
    assert Proc === @rapp.rack_app, "Rack application should be a Proc"
    assert Gin::Router === @app.router, "Should have a Gin::Router"
    assert @app.router.resources_for("get", "/foo"),
      "App should route GET /foo"
  end


  def test_init_missing_routes
    assert_raises Gin::RouterError do
      MissingRouteApp.new
    end
  end


  def test_init_extra_routes
    assert_raises Gin::RouterError do
      ExtraRouteApp.new
    end
  end


  def test_default_environment
    assert_equal 'development', FooApp.environment
  end


  def test_default_inst_environment
    assert @app.development?
    assert !@app.test?
    assert !@app.staging?
    assert !@app.production?
  end


  def test_environment
    ENV['RACK_ENV'] = 'production'
    FooApp.setup
    assert_equal 'production', FooApp.environment
  end


  def test_inst_environment
    ENV['RACK_ENV'] = 'production'
    FooApp.setup
    @app = FooApp.new
    assert !@app.development?
    assert !@app.test?
    assert !@app.staging?
    assert @app.production?
  end


  def test_set_environment
    %w{development test staging production}.each do |name|
      FooApp.environment name
      @app = FooApp.new
      mname = name + "?"
      assert @app.send(mname), "Instance environment should be #{name}"
    end
  end


  def test_build_w_middleware
    FooApp.sessions true
    FooApp.protection true
    @app = FooApp.new
    stack = @app.instance_variable_get("@stack")
    assert Rack::Session::Cookie === stack
    assert Rack::Protection::FrameOptions === stack.instance_variable_get("@app")

    while stack = stack.instance_variable_get("@app")
      app = stack
      break if @app == app
    end

    assert_equal @app, app
  end


  def test_build_no_middleware
    stack = @app.instance_variable_get("@stack")
    assert_equal @app, stack
  end
end
