module Gin::Errorable
  extend GinClass

  def self.included klass
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

    def error *err_types, &block
      return unless block_given?
      err_types << nil if err_types.empty?

      err_types.each do |name|
        self.local_error_handlers[name] = block
      end
    end


    ##
    # Run after an error has been raised and optionally handled by an
    # error callback. The block will get run on all errors and is given
    # the exception instance as an argument.

    def all_errors &block
      return unless block_given?
      self.local_error_handlers[:all] = block
    end


    ##
    # Hash of error handlers defined by Gin::Controller.error.
    # This attribute is inherited.

    def error_handlers
      inherited = self.superclass.respond_to?(:error_handlers) ?
                          self.superclass.error_handlers : {}
      inherited.merge local_error_handlers
    end


    def local_error_handlers #:nodoc:
      @err_handlers ||= {}
    end
  end


  class_proxy_reader :error_handlers

  ##
  # Calls the appropriate error handlers for the given error.
  # Re-raises the error if no handler is found.

  def handle_error err
    (@env['gin.errors'] ||= []) << err
    status(err.http_status) if err.respond_to?(:http_status)
    status(500) unless (400..599).include? status

    key = self.error_handlers.keys.find{|key| key === err }
    raise err unless key || self.error_handlers[:all]

    instance_exec(err, &self.error_handlers[key])  if key
    instance_exec(err, &self.error_handlers[:all]) if self.error_handlers[:all]
  end


  ##
  # Calls the appropriate error handlers for the given status code.

  def handle_status code
    handler = self.error_handlers[code]
    instance_exec(&handler) if handler
  end
end
