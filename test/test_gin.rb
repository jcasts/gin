require 'test/test_helper'

class GinTest < Test::Unit::TestCase

  def test_underscore
    assert_equal "foo_bar", Gin.underscore("FooBar")
    assert_equal "foo_bar", Gin.underscore("fooBar")
    assert_equal "foo_bar", Gin.underscore("foo_Bar")
    assert_equal "foo_http", Gin.underscore("fooHTTP")
    assert_equal "foo_http_thing", Gin.underscore("fooHTTPThing")
    assert_equal "foo/bar", Gin.underscore("Foo::Bar")
    assert_equal "foo/http", Gin.underscore("Foo::HTTP")
  end


  def test_build_query
    hash = {a: "bob", b: [1,2.2,-3,{ba:"test"}], c:true, d:false}
    expected = "a=bob&b[]=1&b[]=2.2&b[]=-3&b[][ba]=test&c=true&d=false"
    assert_equal expected, Gin.build_query(hash)
  end


  def test_build_query_non_hash
    [[1,2,3], 1, 1.2, "str"].each do |obj|
      assert_raises(ArgumentError, "#{obj.class} did not raise ArgumentError") do
        Gin.build_query obj
      end
    end
  end


  def test_find_loadpath
    assert_equal __FILE__, Gin.find_loadpath("test/test_gin")
    assert_equal __FILE__, Gin.find_loadpath("test/test_gin.rb")
    assert_equal __FILE__, Gin.find_loadpath(__FILE__)
    assert_nil Gin.find_loadpath("FUUUUU")
  end


  def test_const_find
    assert_equal Test::Unit, Gin.const_find("Test::Unit")
    assert_equal Test::Unit, Gin.const_find("Unit", Test)
    assert_raises(NameError){ Gin.const_find("Unit", Gin) }
  end


  def test_app_trace
    trace = [
      Gin::ROOT_DIR + "/blah",
      Gem.path[0]   + "/foo",
      Gin::ROOT_DIR + "/more",
      "/path/to/app/thing"
    ]

    assert_equal ["/path/to/app/thing"], Gin.app_trace(trace)
  end
end
