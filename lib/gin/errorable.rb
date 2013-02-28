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
        self.error_handlers[name] = block
      end
    end


    ##
    # Run after an error has been raised and optionally handled by an
    # error callback. The block will get run on all errors and is given
    # the exception instance as an argument.

    def all_errors &block
      return unless block_given?
      self.error_handlers[:all] = block
    end


    ##
    # Hash of error handlers defined by Gin::Controller.error.
    # This attribute is inherited.

    def error_handlers
      @err_handlers ||= {}
    end


    ##
    # Find the appropriate error handler for the given error.
    # First looks for handler in the current class, then looks
    # in parent classes if none is found.

    def error_handler_for err #:nodoc:
      handler =
        case err
        when Integer
          error_handlers[err] || error_handlers[nil]

        when Exception
          klasses = err.class.ancestors[0...-3]
          key = klasses.find{|klass| error_handlers[klass] }
          error_handlers[key]

        else
          error_handlers[err]
        end

        handler ||
          self.superclass.respond_to?(:error_handler_for) &&
            self.superclass.error_handler_for(err)
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

    handler = error_handler_for(err)
    instance_exec(err, &handler) if handler

    ahandler = error_handler_for(:all)
    instance_exec(err, &ahandler) if ahandler

    raise err unless handler
  end


  def error_handler_for err #:nodoc:
    self.class.error_handler_for err
  end


  ##
  # Calls the appropriate error handlers for the given status code.

  def handle_status code
    handler = error_handler_for(code)
    instance_exec(&handler) if handler
  end
end
