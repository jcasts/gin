
##
# App made for testing

class AppFoo < Gin::App

  errors ErrorController

  mount FooController, "/foo" do
    get  :index,  "/"
    post :create, "/"
  end

  mount BlahController
end
