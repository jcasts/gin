class Gin::Controller
  extend GinClass

  class InvalidFilterError < Gin::Error; end

  ##
  # String representing the controller name.
  # Underscores the class name and removes mentions of 'controller'.
  #   MyApp::FooController.controller_name
  #   #=> "my_app/foo"

  def self.controller_name
    @ctrl_name ||= self.to_s.underscore.gsub(/_?controller_?/,'')
  end


  ##
  # Define an error handler for this Controller. Configurable with exceptions
  # or status codes.
  #   error 502, 503, 504 do
  #     # handle unexpected upstream error
  #   end
  #
  #   error do |err|
  #     # catch-all
  #   end
  #
  #   error Timeout::Error do |err|
  #     # something timed out
  #   end

  def self.error err_type, &block
    
  end


  ##
  # Create a filter for controller actions. If the filter's return value is
  # false-ish it will raise an error, specified by throw_err.
  # By default filters throw a 403 error.
  #   filter :logged_in, 401 do
  #     @user && @user.logged_in?
  #   end
  #
  # Use Gin::Controller.before_filter and Gin::Controller.after_filter to
  # apply filters.

  def self.filter name, throw_err=nil, &block
    throw_err ||= 403
    @filters ||= {}
    @filters[name.to_sym] = [throw_err, block]
  end


  ##
  # Assign one or more filters to run before calling an action.
  # Set for all actions by default.
  # Supports an options hash as the last argument with :only and :except
  # keys.
  #   before_filter :logged_in, :except => :index

  def self.before_filter filter, *filters
    
  end


  ##
  # Assign one or more filters to run after calling an action.
  # Set for all actions by default.
  # Supports an options hash as the last argument with :only and :except
  # keys.
  #   after_filter :clear_cookies, :only => :logout

  def self.after_filter filter, *filters
    
  end


  class_proxy_reader :controller_name

  attr_reader :app, :request, :response


  def initialize env
    @request  = Gin::Request.new env
    @response = Gin::Response.new
  end


  def __call__ action
    # Check and run before filters
    # Call action
    # Check and run after filters
  rescue => err
    # Check for error handling or re-raise
  end


  def filter name, *names
    names.unshift name
    names.each do |n|
      throw_err, block = @filters[name.to_sym] = [throw_err, block]
      raise InvalidFilterError, "No block to run for filter #{n}" unless block
      # TODO: figure out how to correctly throw these errors/status codes
      raise throw_err unless block.call
    end
  end
end
