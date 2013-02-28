require 'test/test_helper'

class ResponseTest < Test::Unit::TestCase

  def setup
    @res = Gin::Response.new
  end


  def test_assign_body
    @res.body = "foo"
    assert_equal ["foo"], @res.body

    @res.body = ["bar"]
    assert_equal ["bar"], @res.body

    rack_resp = Rack::Response.new
    rack_resp.body = "rack_body"
    @res.body = rack_resp
    assert_equal ["rack_body"], @res.body
  end


  def test_finish
    @res.body = "foo"
    expected = [200,
      {"Content-Type"=>"text/html", "Content-Length"=>"3"},
      ["foo"]]

    assert_equal expected, @res.finish
  end


  def test_finish_bodyless
    [204, 205, 304].each do |code|
      @res['Content-Type']   = "application/json"
      @res['Content-Length'] = "123"
      @res.status = code
      @res.body   = "foo"
      expected    = [code, {}, []]

      assert_equal expected, @res.finish
    end
  end


  def test_finish_no_ctype_clen
    [100, 101].each do |code|
      @res['Content-Type']   = "application/json"
      @res['Content-Length'] = "123"
      @res.status = code
      @res.body   = "foo"
      expected    = [code, {}, ["foo"]]

      assert_equal expected, @res.finish
    end
  end
end
