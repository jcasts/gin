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

    before_filter :custom_thing

    skip_before_filter :find_device
    skip_before_filter :logged_in, :only => [:create, :new]
    skip_after_filter :set_login_cookie, :except => [:logout]
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
      AppCtrl.before_filters.map{|(n,_)| n }

    assert_equal [:logged_in, :custom_thing],
      SessionCtrl.before_filters.map{|(n,_)| n }

    assert_equal [:log_action, :set_login_cookie, :other_filter],
      AppCtrl.after_filters.map{|(n,_)| n }

    assert_equal [:log_action, :set_login_cookie, :other_filter],
      SessionCtrl.after_filters.map{|(n,_)| n }
  end


  def test_filter_rule_inheritance
    assert_nil AppCtrl.before_filters.first[1]
    assert_equal({:except => [:foo]}, AppCtrl.after_filters.last[1])

    assert_equal({:except => [:create, :new]},
      SessionCtrl.before_filters.first[1])
    assert_equal({:except => [:foo], :only => [:logout]},
      SessionCtrl.after_filters[-2][1])
    assert_equal({:except => [:foo]},
      SessionCtrl.after_filters[-1][1])
  end


  def test_filter_action_validation
    assert @session_ctrl.send(:__valid_filter__, :action, nil)

    assert @session_ctrl.send(:__valid_filter__, :action, :only => [:action])
    assert @session_ctrl.send(:__valid_filter__, :action, :except => [:other])

    assert !@session_ctrl.send(:__valid_filter__, :action, :except => [:action])
    assert !@session_ctrl.send(:__valid_filter__, :action, :only => [:other])
  end


  def test_call_filters
    @app_ctrl.send(:__call_filters__, @app_ctrl.before_filters, :action)
    assert_equal [:logged_in, :find_device], FILTER_CALLS

    FILTER_CALLS.clear
    @session_ctrl.send(:__call_filters__, @session_ctrl.before_filters, :action)
    assert_equal [:logged_in, :custom_thing], FILTER_CALLS
  end


  def test_call_filters_with_restrictions
    @app_ctrl.send(:__call_filters__, @app_ctrl.before_filters, :create)
    assert_equal [:logged_in, :find_device], FILTER_CALLS

    FILTER_CALLS.clear
    @session_ctrl.send(:__call_filters__, @session_ctrl.before_filters, :create)
    assert_equal [:custom_thing], FILTER_CALLS
  end


  def test_filter_calls
    @session_ctrl.filter :logged_in, :custom_thing, :other_filter
    assert_equal [:logged_in, :custom_thing, :other_filter], FILTER_CALLS
  end
end
