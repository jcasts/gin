require "test/test_helper"

class AppTest < Test::Unit::TestCase

  class FooController < Gin::Controller; end

  class FooApp < Gin::App
    mount FooController do
      get :index, "/"
    end
  end


  def setup
    @app  = FooApp.new
    @rapp = FooApp.new lambda{|env| [200,{'Content-Type'=>'text/html'},["HI"]]}
  end
end
