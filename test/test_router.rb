require "test/test_helper"

class MyCtrl < Gin::Controller;
  def unmounted_action; end
end

class FooController < Gin::Controller; end


class RouterTest < Test::Unit::TestCase

  def setup
    @router = Gin::Router.new
  end


  def test_add_and_retrieve
    @router.add MyCtrl, '/my_ctrl' do
      get  :bar, "/bar"
      post :foo
      any  :thing
    end

    assert_equal [MyCtrl, :bar, {}],
      @router.resources_for("GET", "/my_ctrl/bar")

    assert_equal [MyCtrl, :foo, {}],
      @router.resources_for("post", "/my_ctrl/foo")

    assert_nil @router.resources_for("post", "/my_ctrl")

    %w{get post put delete head options trace}.each do |verb|
      assert_equal [MyCtrl, :thing, {}],
        @router.resources_for(verb, "/my_ctrl/thing")
    end
  end


  def test_add_and_retrieve_named_route
    @router.add FooController, "/foo" do
      get  :index, "/", :all_foo
      get  :bar, :my_bar
      post :create
    end

    assert_equal [FooController, :bar, {}],
      @router.resources_for("GET", "/foo/bar")

    assert_equal "/foo/bar", @router.path_to(:my_bar)
    assert_equal "/foo/create", @router.path_to(:create_foo)
    assert_equal "/foo", @router.path_to(:all_foo)
  end


  def test_add_and_retrieve_w_path_params
    @router.add MyCtrl, '/my_ctrl/:str' do
      get  :bar, "/bar"
      post :foo, "/"
    end

    assert_nil @router.resources_for("post", "/my_ctrl")

    assert_equal [MyCtrl, :bar, {'str' => 'item'}],
      @router.resources_for("GET", "/my_ctrl/item/bar")

    assert_equal [MyCtrl, :foo, {'str' => 'item'}],
      @router.resources_for("post", "/my_ctrl/item")
  end


  def test_add_omit_base_path
    @router.add MyCtrl do
      get :bar
    end

    assert_equal [MyCtrl, :bar, {}],
      @router.resources_for("GET", "/my_ctrl/bar")
  end


  def test_add_omit_base_path_controller
    @router.add FooController do
      get :index, '/'
    end

    assert_equal [FooController, :index, {}],
      @router.resources_for("GET", "/foo")
  end


  def test_add_root_base_path
    @router.add MyCtrl, "/" do
      get :bar, "/"
    end

    assert_equal [MyCtrl, :bar, {}],
      @router.resources_for("GET", "/")
  end


  def test_has_route
    @router.add MyCtrl, '/my_ctrl/:str' do
      get  :bar, "/bar"
      post :foo, "/"
    end

    assert @router.has_route?(MyCtrl, :bar)
    assert @router.has_route?(MyCtrl, :foo)
    assert !@router.has_route?(MyCtrl, :thing)
  end


  def test_path_to
    @router.add MyCtrl, '/my_ctrl/' do
      get :bar, "/bar"
    end

    assert_equal "/my_ctrl/bar", @router.path_to(MyCtrl, :bar)
  end


  def test_path_to_missing
    @router.add MyCtrl, '/my_ctrl/' do
      get :bar, "/bar"
    end

    assert_raises Gin::Router::PathArgumentError do
      @router.path_to(MyCtrl, :foo)
    end
  end


  def test_path_to_param
    @router.add MyCtrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    assert_equal "/my_ctrl/val", @router.path_to(MyCtrl, :show, "id" => "val")

    assert_equal "/my_ctrl/val", @router.path_to(MyCtrl, :show, :id => "val")
  end


  def test_path_to_param_missing
    @router.add MyCtrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    assert_raises Gin::Router::PathArgumentError do
      @router.path_to(MyCtrl, :show)
    end
  end
end
