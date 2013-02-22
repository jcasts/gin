module Gin::Errorable
  extend GinClass

  def self.inherited klass
    klass.extend ClassMethods
  end


  module ClassMethods

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
    # This attribute is inherited.

    def self.error_handlers
      @err_handlers ||= self.superclass.respond_to?(:error_handlers) ?
                          self.superclass.error_handlers.dup : {}
    end


    ##
    # Set or get the default content type for this Gin::Controller.
    # Default value is "text/html". This attribute is inherited.

    def self.content_type new_type=nil
      return @content_type = new_type if new_type
      @content_type ||= self.superclass.respond_to?(:content_type) ?
                          self.superclass.content_type.dup : "text/html"
    end
  end


  class_proxy_reader :err_handlers

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
end
