class AppController < Gin::Controller

  error 401 do
    # handle error here
  end


  error /[45]\d\d/ do
    # handle error here
  end


  filter :logged_in, 401 do
    # Make sure we're logged in
  end
end
