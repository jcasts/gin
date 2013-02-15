class Gin::Controller
  extend Gin::Callback

  def self.controller_name
    @ctrl_name ||= self.to_s.underscore.gsub(/_?controller_?/,'')
  end

  def self.error err_type, &block
  end


  attr_reader :app, :request, :response


  def initialize app, env
    @app = app
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


  def filters name, *names
    names.unshift name
    names.each do |n|
      # Call filter if it exists, or raise error
    end
  end
end
