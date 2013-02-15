require "test/test_helper"

class AppTest < Test::Unit::TestCase

  class FooController < Gin::Controller; end

  class FooApp < Gin::App
    mount FooController do
      get :index, "/"
    end
  end


  def setup
    FooApp.instance_variable_set("@environment", nil)
    @app  = FooApp.new
    @rapp = FooApp.new lambda{|env| [200,{'Content-Type'=>'text/html'},["HI"]]}
  end


  def test_default_environment
    assert FooApp.development?
    assert !FooApp.test?
    assert !FooApp.staging?
    assert !FooApp.production?
  end
end
