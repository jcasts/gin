require "test/test_helper"

class MyCtrl < Gin::Controller;
  def index; end
  def show; end
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


  def test_add_and_retrieve_path_matcher
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    expected_params = {'type' => 'sub', 'id' => '123', 'format' => 'json'}
    assert_equal [MyCtrl, :bar, expected_params],
      @router.resources_for("GET", "/bar/sub/123.json")
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

    assert !@router.has_route?(MyCtrl, :show)
    assert !@router.has_route?(MyCtrl, :index)
  end


  def test_add_default_restful_routes
    @router.add MyCtrl, "/" do
      get :show, "/:id"
    end

    assert !@router.has_route?(MyCtrl, :index)
    assert !@router.has_route?(MyCtrl, :unmounted_action)
  end


  def test_add_all_routes_as_defaults
    @router.add MyCtrl, "/" do
      get :show, "/:id"
      defaults
    end

    assert @router.has_route?(MyCtrl, :index)
    assert @router.has_route?(MyCtrl, :unmounted_action)
  end


  def test_add_all_with_default_verb
    @router.add MyCtrl, "/" do
      get :show, "/:id"
      defaults :post
    end

    assert_equal [MyCtrl, :index, {}],
      @router.resources_for("GET", "/")

    assert_equal [MyCtrl, :show, {'id' => '123'}],
      @router.resources_for("GET", "/123")

    assert_equal [MyCtrl, :unmounted_action, {}],
      @router.resources_for("POST", "/unmounted_action")
  end


  def test_add_all
    @router.add MyCtrl, "/"

    assert_equal [MyCtrl, :index, {}],
      @router.resources_for("GET", "/")

    assert_equal [MyCtrl, :show, {'id' => '123'}],
      @router.resources_for("GET", "/123")

    assert_equal [MyCtrl, :unmounted_action, {}],
      @router.resources_for("GET", "/unmounted_action")
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


  def test_path_to_complex_param
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    params = {'type' => 'sub', 'id' => 123, 'format' => 'json', 'more' => 'hi'}
    assert_equal "/bar/sub/123.json?more=hi", @router.path_to(MyCtrl, :bar, params)
  end


  def test_path_to_complex_param_missing
    @router.add MyCtrl, "/" do
      get :bar, "/bar/:type/:id.:format"
    end

    params = {'type' => 'sub', 'id' => '123', 'more' => 'hi'}
    assert_raises Gin::Router::PathArgumentError do
      @router.path_to(MyCtrl, :bar, params)
    end
  end
end
