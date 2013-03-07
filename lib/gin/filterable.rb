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


    def modify_filter_stack filter_hsh, name, *names #:nodoc:
      names = [name].concat(names)
      opts  = Hash === names[-1] ? names.pop : {}
      names.map!(&:to_sym)

      if opts[:only]
        Array(opts[:only]).each do |action|
          action = action.to_sym
          filter_hsh[action] ||= filter_hsh[nil].dup
          yield filter_hsh, action, names
        end

      elsif opts[:except]
        except = Array(opts[:except])
        filter_hsh.keys.each do |action|
          next if action.nil?
          filter_hsh[action] ||= filter_hsh[nil].dup and next if
            except.include?(action)

          yield filter_hsh, action, names
        end
        yield filter_hsh, nil, names

      else
        filter_hsh.keys.each do |action|
          yield filter_hsh, action, names
        end
      end
    end


    def append_filters filter_hsh, name, *names #:nodoc:
      modify_filter_stack(filter_hsh, name, *names) do |h,k,n|
        h[k].concat n
      end
    end


    def skip_filters filter_hsh, name, *names #:nodoc:
      modify_filter_stack(filter_hsh, name, *names) do |h,k,n|
        h[k] -= n
      end
    end


    ##
    # Assign one or more filters to run before calling an action.
    # Set for all actions by default.
    # This attribute is inherited.
    # Supports an options hash as the last argument with :only and :except
    # keys.
    #
    #   before_filter :logged_in, :except => :index do
    #     verify_session! || halt 401
    #   end

    def before_filter name, *opts, &block
      filter(name, &block) if block_given?
      append_filters(before_filters, name, *opts)
    end


    ##
    # List of before filters.
    # This attribute is inherited.

    def before_filters
      return @before_filters if @before_filters
      @before_filters ||= {nil => []}

      if superclass.respond_to?(:before_filters)
        superclass.before_filters.each{|k,v| @before_filters[k] = v.dup }
      end

      @before_filters
    end


    ##
    # Skip a before filter in the context of the controller.
    # This attribute is inherited.
    # Supports an options hash as the last argument with :only and :except
    # keys.

    def skip_before_filter name, *names
      skip_filters(self.before_filters, name, *names)
    end


    ##
    # Assign one or more filters to run after calling an action.
    # Set for all actions by default.
    # This attribute is inherited.
    # Supports an options hash as the last argument with :only and :except
    # keys.
    #
    #   after_filter :clear_cookies, :only => :logout do
    #     session[:user] = nil
    #   end

    def after_filter name, *opts, &block
      filter(name, &block) if block_given?
      append_filters(self.after_filters, name, *opts)
    end


    ##
    # List of after filters.

    def after_filters
      return @after_filters if @after_filters
      @after_filters ||= {nil => []}

      if superclass.respond_to?(:after_filters)
        superclass.after_filters.each{|k,v| @after_filters[k] = v.dup }
      end

      @after_filters
    end


    ##
    # Skip an after filter in the context of the controller.
    # This attribute is inherited.
    # Supports an options hash as the last argument with :only and :except
    # keys.

    def skip_after_filter name, *names
      skip_filters(self.after_filters, name, *names)
    end


    ##
    # Get an Array of before filter names for the given action.

    def before_filters_for action
      before_filters[action] || before_filters[nil] || []
    end


    ##
    # Get an Array of after filter names for the given action.

    def after_filters_for action
      after_filters[action] || after_filters[nil] || []
    end
  end


  class_proxy :filters, :before_filters, :after_filters,
              :before_filters_for, :after_filters_for

  ##
  # Chain-call filters from an action. Raises the filter exception if any
  # filter in the chain fails.
  #   filter :logged_in, :admin

  def filter *names
    names.each do |n|
      instance_eval(&self.filters[n.to_sym])
    end
  end
end
