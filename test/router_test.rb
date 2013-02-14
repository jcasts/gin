require "test/test_helper"

class RouterTest < Test::Unit::TestCase

  def setup
    @router = Gin::Router.new
  end


  def test_add_and_retrieve
    @router.add :my_ctrl, '/my_ctrl' do
      get  :bar, "/bar"
      post :foo
      any  :thing
    end

    assert_equal [:my_ctrl, :bar, {}],
      @router.resources_for("GET", "/my_ctrl/bar")

    assert_equal [:my_ctrl, :foo, {}],
      @router.resources_for("post", "/my_ctrl/foo")

    assert_nil @router.resources_for("post", "/my_ctrl")

    %w{get post put delete head options trace}.each do |verb|
      assert_equal [:my_ctrl, :thing, {}],
        @router.resources_for(verb, "/my_ctrl/thing")
    end
  end


  def test_add_and_retrieve_w_path_parans
    @router.add :my_ctrl, '/my_ctrl/:str' do
      get  :bar, "/bar"
      post :foo, "/"
    end

    assert_nil @router.resources_for("post", "/my_ctrl")

    assert_equal [:my_ctrl, :bar, {'str' => 'item'}],
      @router.resources_for("GET", "/my_ctrl/item/bar")

    assert_equal [:my_ctrl, :foo, {'str' => 'item'}],
      @router.resources_for("post", "/my_ctrl/item")
  end


  def test_path_for
    @router.add :my_ctrl, '/my_ctrl/' do
      get :bar, "/bar"
    end

    assert_equal "/my_ctrl/bar", @router.path_for(:my_ctrl, :bar)
  end


  def test_path_for_missing
    @router.add :my_ctrl, '/my_ctrl/' do
      get :bar, "/bar"
    end

    assert_raises Gin::InvalidRouteError do
      @router.path_for(:my_ctrl, :foo)
    end
  end


  def test_path_for_param
    @router.add :my_ctrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    assert_equal "/my_ctrl/val", @router.path_for(:my_ctrl, :show, "id" => "val")

    assert_equal "/my_ctrl/val", @router.path_for(:my_ctrl, :show, :id => "val")
  end


  def test_path_for_param_missing
    @router.add :my_ctrl, '/my_ctrl/' do
      get :show, "/:id"
    end

    assert_raises Gin::MissingParamError do
      @router.path_for(:my_ctrl, :show)
    end
  end
end
