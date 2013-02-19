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
  # or status codes. Omitting the err_types argument acts as a catch-all for
  # non-explicitly handled errors.
  #
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

  def self.error *err_types, &block
    return unless block_given?
    err_types << nil if err_types.empty?

    err_types.each do |name|
      self.error_handlers[name] = block
    end
  end


  ##
  # Run after an error has been raised and optionally handled by an
  # error callback. The block will get run on all errors and is given
  # the exception instance as an argument.

  def self.all_errors &block
    return unless block_given?
    self.error_handlers[:all] = block
  end


  ##
  # Hash of error handlers defined by Gin::Controller.error.

  def self.error_handlers
    @err_handlers ||= self.superclass.respond_to?(:error_handlers) ?
                        self.superclass.error_handlers.dup : {}
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
  #
  # Filters may also be called from inside a filter. Watch out for loops!
  #   filter :admin, 403 do
  #     filter :logged_in && @user.admin?
  #   end

  def self.filter name, throw_err=nil, msg=nil, &block
    throw_err ||= 403
    msg       ||= "Filter #{name} failed"
    self.filters[name.to_sym] = [throw_err, msg, block]
  end


  ##
  # Hash of filters defined by Gin::Controller.filter.

  def self.filters
    @filters ||= self.superclass.respond_to?(:filters) ?
                   self.superclass.filters.dup : {}
  end


  ##
  # Assign one or more filters to run before calling an action.
  # Set for all actions by default.
  # Supports an options hash as the last argument with :only and :except
  # keys.
  #   before_filter :logged_in, :except => :index

  def self.before_filter name, *names
    names = [name].concat names
    opts = names.delete_at(-1) if Hash === names[-1]
    self.before_filters << {:names => names, :opts => opts}
  end


  ##
  # List of before filters.

  def self.before_filters
    # TODO: Inheritance needs to deep clone opts key on write
    @before_filters ||= self.superclass.respond_to?(:before_filters) ?
                   self.superclass.before_filters.dup : []
  end


  ##
  # Assign one or more filters to run after calling an action.
  # Set for all actions by default.
  # Supports an options hash as the last argument with :only and :except
  # keys.
  #   after_filter :clear_cookies, :only => :logout

  def self.after_filter name, *names
    names = [name].concat names
    opts = names.delete_at(-1) if Hash === names[-1]
    self.after_filters << {:names => names, :opts => opts}
  end


  ##
  # List of before filters.

  def self.after_filters
    @after_filters ||= self.superclass.respond_to?(:after_filters) ?
                   self.superclass.after_filters.dup : []
  end


  class_proxy_reader :controller_name, :err_handlers
  class_proxy_reader :filters, :before_filters, :after_filters

  attr_reader :app, :request, :response, :action_name


  def initialize app, env
    @app         = app
    @request     = Gin::Request.new env
    @response    = Gin::Response.new
    @action_name = nil
  end


  def __call_action__ action #:nodoc:
    @action_name = action

    __call_before_filters__ action
    __send__ action
    __call_after_filters__ action
    # TODO: assign and return response
    #       allow for streaming

  rescue => err
    handle_error err
  end


  ##
  # Chain-call filters from an action. Raises the filter exception if any
  # filter in the chain fails.
  #   filter :logged_in, :admin

  def filter name, *names
    names.unshift name
    names.each do |n|
      throw_err, msg, block = self.filters[n.to_sym]
      raise InvalidFilterError, "No block to run for filter #{n}" unless block
      throw_err = Gin::HTTP_ERRORS[throw_err] if Integer === throw_err
      raise throw_err, msg unless block.call
    end
  end


  ##
  # Calls the appropriate error handlers for the given error.
  # Re-raises the error if no handler is found.

  def handle_error err
    key = self.error_handlers.keys.find do |key|
            key === err || err.respond_to?(:status) && key === err.status
          end

    raise err unless key || self.error_handlers[:all]

    instance_exec(err, &self.error_handlers[key])  if key
    instance_exec(err, &self.error_handlers[:all]) if self.error_handlers[:all]
  end


  ##
  # Accessor for main application logger.

  def logger
    @app.logger
  end


  ##
  # Get the request params.

  def params
    @request.params
  end


  ##
  # Build a path to the given controller and action, with any expected params.

  def path_to controller, action, params={}
    @app.router.path_to controller, action, params
  end


  ##
  # Returns the full path to an asset

  def asset_path type, name
    
  end


  private


  def __call_before_filters__ action #:nodoc:
    before_filters.each do |fhash|
      filter(*fhash[:names]) if __check_filter_opts__ action, fhash[:opts]
    end
  end


  def __call_after_filters__ action #:nodoc:
    after_filters.each do |fhash|
      filter(*fhash[:names]) if __check_filter_opts__ action, fhash[:opts]
    end
  end


  def __check_filter_opts__ action, opts #:nodoc:
    return true unless opts
    opts.each do |key, val|
    end
  end
end
