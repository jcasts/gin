class MockApp < Gin::App

  class FooController < Gin::Controller
    controller_name "foo"
    layout "foo"

    def index
      view :bar, :locals => {:test_val => "LOCAL"}
    end

    def login
      set_cookie "foo_session", "12345",
        :expires => Time.parse("Fri, 01 Jan 2100 00:00:00 -0000")
      "OK"
    end

    def supercookie
      set_cookie "supercookie", "SUPER!",
        :expires =>  Time.parse("Fri, 01 Jan 2100 00:00:00 -0000"),
        :domain =>   "mockapp.com",
        :path =>     "/",
        :secure =>   true,
        :httponly => true
      "OK"
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

    def see_other
      redirect "http://example.com", 301
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


  logger StringIO.new
  root_dir "test/app"

  autoreload false

  mount BarController do
    get :show, "/:id"
    get :index, "/"
    defaults
  end

  mount FooController

  mount ApiController
end
