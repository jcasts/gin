require 'test/test_helper'

class RequestTest < Test::Unit::TestCase

  def setup
    @env = {
      'HTTP_HOST' => 'example.com',
      'rack.input' => '',
      'QUERY_STRING' =>
        'id=456&foo=bar&bar=5&bool=true&nbool=truefalse&zip=01234&nint=m3&nflt=01.123&neg=-12&negf=-2.1',
      'gin.path_query_hash' => {'id' => 123},
    }
    @req = Gin::Request.new @env
  end


  def test_query_hash_as_param
    assert_equal 123, @req.params['id']
    assert_equal 'bar', @req.params['foo']
    assert_equal 5, @req.params['bar']
    assert_equal '01234', @req.params['zip']
    assert_equal 'm3', @req.params['nint']
    assert_equal '01.123', @req.params['nflt']
    assert_equal -12, @req.params['neg']
    assert_equal -2.1, @req.params['negf']
  end


  def test_params_symbol_accessible
    [:id, :foo, :bar].each do |key|
      assert @req.params[key]
    end
  end


  def test_forwarded
    assert !@req.forwarded?
    @env["HTTP_X_FORWARDED_HOST"] = "example.com"
    assert @req.forwarded?
  end


  def test_ssl
    assert !@req.ssl?

    @env['HTTPS'] = 'on'
    assert @req.ssl?
  end


  def test_safe
    @env['REQUEST_METHOD'] = 'POST'
    assert !@req.safe?, "Verb POST should NOT be safe"

    %w{GET HEAD OPTIONS TRACE}.each do |verb|
      @env['REQUEST_METHOD'] = verb
      assert @req.safe?, "Verb #{verb} should be safe"
    end
  end


  def test_idempotent
    @env['REQUEST_METHOD'] = 'POST'
    assert !@req.idempotent?, "Verb POST should NOT be idempotent"

    %w{GET HEAD OPTIONS TRACE PUT DELETE}.each do |verb|
      @env['REQUEST_METHOD'] = verb
      assert @req.idempotent?, "Verb #{verb} should be idempotent"
    end
  end


  def test_process_params
    assert_equal true,  @req.send(:process_params, "true")
    assert_equal false, @req.send(:process_params, "false")
    assert_equal 1,     @req.send(:process_params, "1")
    assert_equal 1.1,   @req.send(:process_params, "1.1")
    assert_equal "w1",  @req.send(:process_params, "w1")
    assert_equal "not_true", @req.send(:process_params, "not_true")

    ary = @req.send(:process_params, ["true", "1", "foo"])
    assert_equal [true, 1, "foo"], ary

    hash = @req.send(:process_params, {'key' => ["true", "1", "foo"]})
    assert_equal [true, 1, "foo"], hash['key']
    assert_equal hash['key'].object_id, hash[:key].object_id
  end
end
