require "test/test_helper"

class AppTest < Test::Unit::TestCase

  class FooApp < Gin::App
  end


  def setup
    @app  = FooApp.new
    @rapp = FooApp.new lambda{|env| [200,{'Content-Type'=>'text/html'},["HI"]]}
  end
end
