module Gin::Filterable

  extend GinClass

  class InvalidFilterError < Gin::Error; end

  def self.included klass
    klass.extend ClassMethods
  end


  module ClassMethods

    ##
    # Create a filter for controller actions.
    #   filter :logged_in do
    #     @user && @user.logged_in?
    #   end
    #
    # Use Gin::Controller.before_filter and Gin::Controller.after_filter to
    # apply filters.

    def filter name, &block
      self.filters[name.to_sym] = block
    end


    ##
    # Hash of filters defined by Gin::Controller.filter.
    # This attribute is inherited.

    def filters
      @filters ||= self.superclass.respond_to?(:filters) ?
                     self.superclass.filters.dup : {}
    end


    def append_filters filter_ary, name, *names #:nodoc:
      names = [name].concat names
      opts  = normalize_filter_opts names.delete_at(-1) if Hash === names[-1]

      filter_ary.concat names.map{|n| [n.to_sym, opts] }
    end


    def skip_filters filter_ary, name, *names #:nodoc:
      names = [name].concat names

      if Hash === names[-1]
        opts = normalize_filter_opts names.delete_at(-1)
        opts[:except], opts[:only] = opts[:only], opts[:except]

        filter_ary.length.times do |i|
          fname, old_opts = filter_ary[i]
          next unless names.include? fname

          old_opts ||= {}
          new_opts   = {}

          new_opts[:only] =
            Array(opts[:only]).concat Array(old_opts[:only]) if
            old_opts[:only] || opts[:only]

          new_opts[:except] =
            Array(opts[:except]).concat Array(old_opts[:except]) if
            old_opts[:except] || opts[:except]

          filter_ary[i] = [fname, new_opts]
        end

      else
        filter_ary.delete_if{|(fname,_)| names.include? fname }
      end
    end


    def normalize_filter_opts opts #:nodoc:
      opts[:only]   = Array(opts[:only])   if opts[:only]
      opts[:except] = Array(opts[:except]) if opts[:except]
      opts
    end


    ##
    # Assign one or more filters to run before calling an action.
    # Set for all actions by default.
    # This attribute is inherited.
    # Supports an options hash as the last argument with :only and :except
    # keys.
    #   before_filter :logged_in, :except => :index

    def before_filter name, *names
      append_filters(self.before_filters, name, *names)
    end


    ##
    # List of before filters.
    # This attribute is inherited.

    def before_filters
      @before_filters ||= self.superclass.respond_to?(:before_filters) ?
                     self.superclass.before_filters.dup : []
    end


    ##
    # Skip a before filter in the context of the controller.
    # This attribute is inherited.

    def skip_before_filter name, *names
      skip_filters(self.before_filters, name, *names)
    end


    ##
    # Assign one or more filters to run after calling an action.
    # Set for all actions by default.
    # This attribute is inherited.
    # Supports an options hash as the last argument with :only and :except
    # keys.
    #   after_filter :clear_cookies, :only => :logout

    def after_filter name, *names
      append_filters(self.after_filters, name, *names)
    end


    ##
    # List of before filters.
    # This attribute is inherited.

    def after_filters
      @after_filters ||= self.superclass.respond_to?(:after_filters) ?
                     self.superclass.after_filters.dup : []
    end


    ##
    # Skip an after filter in the context of the controller.
    # This attribute is inherited.

    def skip_after_filter name, *names
      skip_filters(self.after_filters, name, *names)
    end
  end



  class_proxy_reader :filters, :before_filters, :after_filters

  ##
  # Chain-call filters from an action. Raises the filter exception if any
  # filter in the chain fails.
  #   filter :logged_in, :admin

  def filter name, *names
    names.unshift name
    names.each do |n|
      instance_eval(&self.filters[n.to_sym])
    end
  end


  private


  def __call_filters__ filter_ary, action #:nodoc:
    filter_ary.each do |name, opts|
      filter(name) if __valid_filter__ action, opts
    end
  end


  def __valid_filter__ action, opts #:nodoc:
    return true unless opts

    return false if opts[:only] && !opts[:only].include?(action) ||
                    opts[:except] && opts[:except].include?(action)

    true
  end
end
