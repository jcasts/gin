require 'test/test_helper'

class FilterableTest < Test::Unit::TestCase

  FILTER_CALLS = []

  class AppCtrl
    include Gin::Filterable

    class << self
      attr_accessor :is_logged_in
    end

    self.is_logged_in = true

    filter :logged_in do
      FILTER_CALLS << :logged_in
      self.class.is_logged_in
    end

    filter :find_device do
      FILTER_CALLS << :find_device
      "iPhone"
    end

    filter :log_action do
      FILTER_CALLS << :log_action
      "foo"
    end

    filter :set_login_cookie do
      FILTER_CALLS << :set_login_cookie
      "COOKIES"
    end

    filter :other_filter do
      FILTER_CALLS << :other_filter
      "other_filter"
    end

    before_filter :logged_in
    before_filter :find_device

    after_filter :log_action
    after_filter :set_login_cookie, :other_filter, :except => :foo


    private

    def __call_filters__ type, action
      filter(*__send__(:"#{type}_filters_for", action))
    end
  end


  class SessionCtrl < AppCtrl
    class << self
      attr_accessor :is_custom_thing
    end

    self.is_logged_in = true
    self.is_custom_thing = true

    filter :custom_thing do
      FILTER_CALLS << :custom_thing
      self.class.is_custom_thing
    end

    filter :only_foo do
      FILTER_CALLS << :only_foo
      "onlyfoo"
    end

    before_filter :custom_thing

    skip_before_filter :find_device
    skip_before_filter :logged_in, :only => [:create, :new]
    skip_after_filter :set_login_cookie, :except => [:logout]

    after_filter :only_foo, :only => :foo
  end



  def setup
    FILTER_CALLS.clear
    @app_ctrl = AppCtrl.new
    @session_ctrl = SessionCtrl.new
    SessionCtrl.is_logged_in = true
    SessionCtrl.is_custom_thing = true
  end


  def test_filter_chain_inheritance
    assert_equal [:logged_in, :find_device],
      AppCtrl.before_filters[nil]

    assert_equal [:logged_in, :custom_thing],
      SessionCtrl.before_filters[nil]

    assert_equal [:log_action, :set_login_cookie, :other_filter],
      AppCtrl.after_filters[nil]

    assert_equal [:log_action, :other_filter],
      SessionCtrl.after_filters[nil]
  end


  def test_filter_chain_exceptions
    assert_equal [:log_action], AppCtrl.after_filters[:foo]
    assert_equal [:log_action, :only_foo], SessionCtrl.after_filters[:foo]
    assert_equal [:log_action, :set_login_cookie, :other_filter],
                  SessionCtrl.after_filters[:logout]
  end


  def test_call_filters
    @app_ctrl.send(:__call_filters__, :before, :action)
    assert_equal [:logged_in, :find_device], FILTER_CALLS

    FILTER_CALLS.clear
    @session_ctrl.send(:__call_filters__, :before, :action)
    assert_equal [:logged_in, :custom_thing], FILTER_CALLS
  end


  def test_call_filters_with_restrictions
    @app_ctrl.send(:__call_filters__, :before, :create)
    assert_equal [:logged_in, :find_device], FILTER_CALLS

    FILTER_CALLS.clear
    @session_ctrl.send(:__call_filters__, :before, :create)
    assert_equal [:custom_thing], FILTER_CALLS
  end


  def test_filter_calls
    @session_ctrl.filter :logged_in, :custom_thing, :other_filter
    assert_equal [:logged_in, :custom_thing, :other_filter], FILTER_CALLS
  end
end
