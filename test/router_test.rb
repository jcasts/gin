require "test/test_helper"

class RouterTest < Test::Unit::TestCase

  class MyCtrl; end

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
      @router.resources_for("GET", "/router_test/my_ctrl/bar")
  end


  def test_add_root_base_path
    @router.add MyCtrl, "/" do
      get :bar, "/"
    end

    assert_equal [MyCtrl, :bar, {}],
      @router.resources_for("GET", "/")
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
