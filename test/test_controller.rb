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

class TestController < Gin::Controller
  def show id
    "SHOW #{id}!"
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
    MockApp.instance_variable_set("@environment", nil)
    MockApp.instance_variable_set("@asset_host", nil)
    @app  = MockApp.new StringIO.new
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


  def test_config
    assert_equal @ctrl.app.config.object_id, @ctrl.config.object_id
  end


  def test_etag
    @ctrl.etag("my-etag")
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    @ctrl.etag("my-etag", kind: :strong)
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    @ctrl.etag("my-etag", :strong)
    assert_equal "my-etag".inspect, @ctrl.response['ETag']
  end


  def test_etag_weak
    @ctrl.etag("my-etag", kind: :weak)
    assert_equal 'W/"my-etag"', @ctrl.response['ETag']

    @ctrl.etag("my-etag", :weak)
    assert_equal 'W/"my-etag"', @ctrl.response['ETag']
  end


  def test_etag_if_match
    rack_env['HTTP_IF_MATCH'] = '"other-etag"'
    resp = catch(:halt){ @ctrl.etag "my-etag" }
    assert_equal 412, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    rack_env['HTTP_IF_MATCH'] = '*'
    resp = catch(:halt){ @ctrl.etag "my-etag" }
    assert_equal nil, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    rack_env['HTTP_IF_MATCH'] = '*'
    resp = catch(:halt){ @ctrl.etag "my-etag", new_resource: true }
    assert_equal 412, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    rack_env['REQUEST_METHOD'] = 'POST'
    rack_env['HTTP_IF_MATCH'] = '*'
    resp = catch(:halt){ @ctrl.etag "my-etag" }
    assert_equal 412, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']
  end


  def test_etag_if_none_match
    rack_env['REQUEST_METHOD'] = 'GET'

    rack_env['HTTP_IF_NONE_MATCH'] = '"other-etag"'
    resp = catch(:halt){ @ctrl.etag "my-etag" }
    assert_equal nil, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    rack_env['HTTP_IF_NONE_MATCH'] = '"other-etag", "my-etag"'
    resp = catch(:halt){ @ctrl.etag "my-etag" }
    assert_equal 304, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    rack_env['HTTP_IF_NONE_MATCH'] = '*'
    resp = catch(:halt){ @ctrl.etag "my-etag" }
    assert_equal 304, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']

    rack_env['REQUEST_METHOD'] = 'POST'
    rack_env['HTTP_IF_NONE_MATCH'] = '*'
    resp = catch(:halt){ @ctrl.etag "my-etag", new_resource: false }
    assert_equal 412, resp
    assert_equal "my-etag".inspect, @ctrl.response['ETag']
  end


  def test_etag_non_error_status
    [200, 201, 202, 304].each do |code|
      @ctrl.status code
      rack_env['HTTP_IF_MATCH'] = '"other-etag"'
      resp = catch(:halt){ @ctrl.etag "my-etag" }
      assert_equal 412, resp
      assert_equal "my-etag".inspect, @ctrl.response['ETag']
    end
  end


  def test_etag_error_status
    [301, 302, 303, 400, 404, 500, 502, 503].each do |code|
      @ctrl.status code
      rack_env['HTTP_IF_MATCH'] = '"other-etag"'
      resp = catch(:halt){ @ctrl.etag "my-etag" }
      assert_equal nil, resp
      assert_equal "my-etag".inspect, @ctrl.response['ETag']
    end
  end


  def test_cache_control
    @ctrl.cache_control :public, :must_revalidate, max_age: 60
    assert_equal "public, must-revalidate, max-age=60",
                 @ctrl.response['Cache-Control']

    @ctrl.cache_control public:true, must_revalidate:false, max_age:'foo'
    assert_equal "public, max-age=0", @ctrl.response['Cache-Control']
  end


  def test_expires_int
    time = Time.now
    @ctrl.expires 60, :public, :must_revalidate

    assert_equal "public, must-revalidate, max-age=60",
                 @ctrl.response['Cache-Control']

    assert_equal (time + 60).httpdate, @ctrl.response['Expires']
  end


  def test_expires_time
    time = Time.now + 60
    @ctrl.expires time, :public, must_revalidate:false, max_age:20

    assert_equal "public, max-age=20",
                 @ctrl.response['Cache-Control']

    assert_equal time.httpdate, @ctrl.response['Expires']
  end


  def test_expires_str
    time = Time.now + 60
    @ctrl.expires time.strftime("%Y/%m/%d %H:%M:%S"),
                  :public, must_revalidate:false, max_age:20

    assert_equal "public, max-age=20",
                 @ctrl.response['Cache-Control']

    assert_equal time.httpdate, @ctrl.response['Expires']
  end


  def test_expire_cache_control
    @ctrl.expire_cache_control
    assert_equal 'no-cache', @ctrl.response['Pragma']
    assert_equal 'no-cache, no-store, must-revalidate, max-age=0',
                  @ctrl.response['Cache-Control']
    assert_equal Gin::Constants::EPOCH.httpdate,
                  @ctrl.response['Expires']
  end


  def test_set_cookie
    exp = Time.now + 360
    cookie = {:value => "user@example.com", :expires => exp}

    @ctrl.set_cookie "test", "user@example.com", :expires => exp
    expected = "test=user%40example.com; expires=#{exp.gmtime.strftime("%a, %d %b %Y %H:%M:%S -0000")}"
    assert_equal expected, @ctrl.response['Set-Cookie']

    @ctrl.set_cookie "test", :path => "/"
    expected << "\ntest=; path=/"
    assert_equal expected, @ctrl.response['Set-Cookie']
  end


  def test_delete_cookie
    test_set_cookie

    @ctrl.delete_cookie "test"
    assert_equal "test=; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 -0000",
                 @ctrl.response['Set-Cookie']
  end


  def test_set_session
    @ctrl.session['test'] = 'user@example.com'
    assert_equal({"test"=>"user@example.com"}, @ctrl.env['rack.session'])
  end


  def test_call_action
    resp = @ctrl.call_action(:show)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal [200, {"Content-Type"=>"text/html;charset=UTF-8", "Content-Length"=>"9"},
      ["SHOW 123!"]], resp
  end


  def test_call_action_error
    @ctrl.call_action(:index)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
  end


  def test_call_action_caught_error
    resp = @ctrl.call_action(:caught_error)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal [400, {"Content-Type"=>"text/html;charset=UTF-8", "Content-Length"=>"11"},
      ["Bad Request"]], resp
  end


  def test_call_action_halt
    resp = @ctrl.call_action(:delete)
    assert_equal [:f1, :stop, :f2], BarController::FILTERS_RUN
    assert_equal [404, {"Content-Type"=>"text/plain;charset=UTF-8", "Content-Length"=>"41"},
      ["This is not the page you are looking for."]], resp
  end


  def test_dispatch
    @ctrl.send(:dispatch, :show)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal 200, @ctrl.response.status
    assert_equal ["SHOW 123!"], @ctrl.response.body
  end


  def test_dispatch_error
    @ctrl.content_type :json
    @ctrl.send(:dispatch, :index)
    assert_equal [:f1, :f2], BarController::FILTERS_RUN
    assert_equal 500, @ctrl.response.status
    assert RuntimeError === @ctrl.env['gin.errors'].first
    assert_equal String, @ctrl.response.body[0].class
    assert_equal "text/html;charset=UTF-8", @ctrl.response['Content-Type']
    assert @ctrl.response.body[0].include?('<h1>RuntimeError</h1>')
    assert @ctrl.response.body[0].include?('<pre>')
  end


  def test_dispatch_error_nondev
    MockApp.environment "prod"
    @ctrl.send(:dispatch, :index)

    assert_equal 500, @ctrl.response.status
    assert RuntimeError === @ctrl.env['gin.errors'].first

    assert_equal File.read(File.join(Gin::PUBLIC_DIR, "500.html")),
                 @ctrl.body.read
  end


  def test_dispatch_bad_request_nondev
    MockApp.environment "prod"
    @ctrl = TestController.new @app, rack_env
    @ctrl.params.delete('id')
    @ctrl.send(:dispatch, :show)

    assert_equal 400, @ctrl.response.status
    assert Gin::BadRequest === @ctrl.env['gin.errors'].first
    assert_equal File.read(File.join(Gin::PUBLIC_DIR, "400.html")),
                 @ctrl.body.read
  end


  def test_dispatch_not_found_nondev
    MockApp.environment "prod"
    @ctrl = TestController.new @app, rack_env
    @ctrl.params.delete('id')
    @ctrl.send(:dispatch, :not_found)

    assert_equal 404, @ctrl.response.status
    assert Gin::NotFound === @ctrl.env['gin.errors'].first
    assert_equal File.read(File.join(Gin::PUBLIC_DIR, "404.html")),
                 @ctrl.body.read
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
    assert_raises(Gin::NotFound){ @ctrl.send("action_arguments", "nonaction") }
    assert_equal [], @ctrl.send("action_arguments", "index")

    assert_equal [123], @ctrl.send("action_arguments", "show")
    assert_equal [123], @ctrl.send("action_arguments", "delete")

    @ctrl.params.update 'name' => 'bob'
    assert_equal [123,nil,'bob'], @ctrl.send("action_arguments", "delete")

    @ctrl.params.delete('id')
    assert_raises(Gin::BadRequest){
      @ctrl.send("action_arguments", "show")
    }
  end


if RUBY_VERSION =~ /^2.0/
  eval <<-EVAL
  class SpecialCtrl < Gin::Controller
    def find(q, title_only:false, count: 10); end
  end
  EVAL

  def test_action_arguments_key_parameters
    @ctrl = SpecialCtrl.new nil, rack_env.merge('QUERY_STRING'=>'q=pizza&count=20')
    assert_equal ["pizza", {count: 20}], @ctrl.send("action_arguments", "find")
  end
end


  def test_asset_url
    old_public_dir = MockApp.public_dir
    MockApp.public_dir File.dirname(__FILE__)

    file_id  = MockApp.md5 __FILE__
    expected = "/test_controller.rb?#{file_id}"

    assert_equal 8, file_id.length
    assert_equal expected, @ctrl.asset_url(File.basename(__FILE__))

  ensure
    MockApp.public_dir old_public_dir
  end


  def test_asset_url_unknown
    assert_equal "/foo.jpg", @ctrl.asset_url("foo.jpg")
  end


  def test_asset_url_w_host
    MockApp.asset_host "http://example.com"
    assert_equal "http://example.com/foo.jpg", @ctrl.asset_url("foo.jpg")

    MockApp.asset_host do |file|
      file =~ /\.js$/ ? "http://js.example.com" : "http://img.example.com"
    end
    assert_equal "http://js.example.com/foo.js",   @ctrl.asset_url("foo.js")
    assert_equal "http://img.example.com/foo.jpg", @ctrl.asset_url("foo.jpg")
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


  def test_last_modified
    time = Time.now
    @ctrl.last_modified time
    assert_equal time.httpdate, @ctrl.response['Last-Modified']

    date = DateTime.parse time.to_s
    @ctrl.last_modified date
    assert_equal time.httpdate, @ctrl.response['Last-Modified']

    date = Date.parse time.to_s
    expected = Time.new(time.year, time.month, time.day)
    @ctrl.last_modified date
    assert_equal expected.httpdate, @ctrl.response['Last-Modified']
  end


  def test_last_modified_str
    time = Time.now
    @ctrl.last_modified time.to_s
    assert_equal time.httpdate, @ctrl.response['Last-Modified']
  end


  def test_last_modified_int
    time = Time.now
    @ctrl.last_modified time.to_i
    assert_equal time.httpdate, @ctrl.response['Last-Modified']
  end


  def test_last_modified_false
    @ctrl.last_modified false
    assert_nil @ctrl.response['Last-Modified']
  end


  def test_last_modified_if_modified_since
    rack_env['HTTP_IF_MODIFIED_SINCE'] = Time.parse("10 Feb 3012").httpdate
    time = Time.now
    @ctrl.status 200
    res = catch(:halt){ @ctrl.last_modified time }

    assert_equal 304, res
    assert_equal time.httpdate, @ctrl.response['Last-Modified']

    rack_env['HTTP_IF_MODIFIED_SINCE'] = Time.parse("10 Feb 2012").httpdate
    time = Time.now
    @ctrl.status 200
    @ctrl.last_modified time
    assert_equal time.httpdate, @ctrl.response['Last-Modified']
  end


  def test_last_modified_if_modified_since_non_200
    rack_env['HTTP_IF_MODIFIED_SINCE'] = Time.parse("10 Feb 3012").httpdate
    time = Time.now
    @ctrl.status 404
    @ctrl.last_modified time
    assert_equal time.httpdate, @ctrl.response['Last-Modified']
  end


  def test_last_modified_if_unmodified_since
    [200, 299, 412].each do |code|
      rack_env['HTTP_IF_UNMODIFIED_SINCE'] = Time.parse("10 Feb 2012").httpdate
      time = Time.now
      @ctrl.status code
      res = catch(:halt){ @ctrl.last_modified time }

      assert_equal 412, res
      assert_equal time.httpdate, @ctrl.response['Last-Modified']

      rack_env['HTTP_IF_MODIFIED_SINCE'] = Time.parse("10 Feb 3012").httpdate
      time = Time.now
      @ctrl.status code
      @ctrl.last_modified time
      assert_equal time.httpdate, @ctrl.response['Last-Modified']
    end
  end


  def test_last_modified_if_unmodified_since_404
    rack_env['HTTP_IF_UNMODIFIED_SINCE'] = Time.parse("10 Feb 2012").httpdate
    time = Time.now
    @ctrl.status 404
    @ctrl.last_modified time

    assert_equal 404, @ctrl.status
    assert_equal time.httpdate, @ctrl.response['Last-Modified']
  end


  def test_send_file
    res = catch(:halt){ @ctrl.send_file "./Manifest.txt" }
    assert_equal 200, res[0]
    assert File === res[1]

    @ctrl.status 404
    @ctrl.send(:invoke){ @ctrl.send_file "./Manifest.txt" }
    assert_equal 200, @ctrl.status
    assert_equal "text/plain;charset=UTF-8", @ctrl.headers["Content-Type"]
    assert_equal File.size("./Manifest.txt").to_s, @ctrl.headers["Content-Length"]
    assert(Time.parse(@ctrl.headers["Last-Modified"]) >
           Time.parse("Fri, 22 Feb 2012 18:51:31 GMT"))
    assert File === @ctrl.body

    read_body = ""
    @ctrl.body.each{|data| read_body << data}
    assert_equal File.read("./Manifest.txt"), read_body
  end


  def test_send_file_not_found
    res = catch(:halt){ @ctrl.send_file "./no-such-file" }
    assert_equal 404, res
  end


  def test_send_file_last_modified
    mod_date = Time.now
    catch(:halt){ @ctrl.send_file "./Manifest.txt", last_modified: mod_date }
    assert_equal mod_date.httpdate, @ctrl.headers["Last-Modified"]
    assert_nil @ctrl.headers['Content-Disposition']
  end


  def test_send_file_attachment
    res = catch(:halt){ @ctrl.send_file "./Manifest.txt", :disposition => 'attachment' }
    expected = "attachment; filename=\"Manifest.txt\""
    assert_equal expected, @ctrl.headers['Content-Disposition']

    res = catch(:halt){
      @ctrl.send_file "./Manifest.txt", :disposition => 'attachment', :filename => "foo.txt"
    }
    expected = "attachment; filename=\"foo.txt\""
    assert_equal expected, @ctrl.headers['Content-Disposition']
  end


  def test_mime_type
    assert_equal "text/html", @ctrl.mime_type(:html)
    assert_equal @ctrl.app.mime_type(:html), @ctrl.mime_type(:html)
  end


  def test_content_type
    assert_nil @ctrl.content_type
    assert_nil @ctrl.response['Content-Type']

    @ctrl.content_type 'text/json'
    assert_equal "text/json;charset=UTF-8", @ctrl.content_type
    assert_equal "text/json;charset=UTF-8", @ctrl.response['Content-Type']

    assert_equal "application/json;charset=UTF-8", @ctrl.content_type(".json")
  end


  def test_content_type_params
    assert_equal "application/json;charset=ASCII-8BIT",
      @ctrl.content_type(".json", charset: "ASCII-8BIT")

    assert_equal "application/json;foo=bar, charset=UTF-8",
      @ctrl.content_type(".json", foo: "bar")
  end


  def test_content_type_unknown
    assert_raises RuntimeError do
      @ctrl.content_type 'fhwbghd'
    end

    assert_equal "text/html;charset=UTF-8",
      @ctrl.content_type('fhwbghd', default: 'text/html')
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
