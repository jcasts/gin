require 'test/test_helper'

class ErrorableTest < Test::Unit::TestCase

  class Foo
    include Gin::Errorable

    def self.delete_all_handlers!
      __setup_errorable
    end

    attr_reader :env

    def initialize
      @status = 200
      @env = {}
    end

    def status val=nil
      @status = val if val
      @status
    end
  end

  class Bar < Foo; end


  def setup
    Foo.delete_all_handlers!
    Bar.delete_all_handlers!
  end


  def test_handler_lookup
    block_404 = lambda{|err| "404" }
    block_err = lambda{|err| "ERROR'D!" }

    Foo.error(404, &block_404)
    Foo.error(Exception, &block_err)

    assert_equal block_404, Foo.error_handler_for(404)
    assert_equal block_err, Foo.error_handler_for(Exception.new)
  end


  def test_handler_local_fallback
    block_def = lambda{|err| "default" }
    Foo.error(&block_def)
    assert_equal block_def, Foo.error_handler_for(404)
    assert_equal block_def, Foo.error_handler_for(ArgumentError.new)

    block_err = lambda{|err| "ERROR'D!" }
    Foo.error(StandardError, &block_err)
    assert_equal block_err, Foo.error_handler_for(ArgumentError.new)
  end


  def test_handler_inheritance
    block_404 = lambda{|err| "404" }
    block_err = lambda{|err| "ERROR'D!" }
    Foo.error(StandardError, &block_err)
    Foo.error(404, &block_404)

    assert_equal block_404, Bar.error_handler_for(404)
    assert_equal block_err, Bar.error_handler_for(ArgumentError.new)
  end


  def test_handler_inheritance_fallback
    block_404 = lambda{|err| "404" }
    block_def = lambda{|err| "default" }
    Foo.error(&block_def)
    Bar.error(404, &block_404)

    assert_equal block_404, Bar.error_handler_for(404)
    assert_equal block_def, Bar.error_handler_for(ArgumentError.new)
  end


  def test_handler_err_inheritance_order
    block_err = lambda{|err| "ERROR'D!" }
    block_def = lambda{|err| "default" }
    Foo.error(ArgumentError, &block_err)
    Bar.error(&block_def)

    assert_equal block_def, Bar.error_handler_for(ArgumentError.new)

    block_err2 = lambda{|err| "ERROR'D!" }
    Bar.error(Exception, &block_err2)

    assert_equal block_err2, Bar.error_handler_for(ArgumentError.new)
  end


  def test_handler_status_inheritance_order
    block_404 = lambda{|err| "404" }
    block_def = lambda{|err| "default" }
    Foo.error(404, &block_404)
    Bar.error(&block_def)

    assert_equal block_def, Bar.error_handler_for(ArgumentError.new)
  end


  def test_handle_status
    handlers = []
    Foo.error{ handlers << :default }
    Foo.all_errors{ handlers << :all }
    Foo.error(404){ handlers << :s404 }

    Foo.new.handle_status(404)
    assert_equal [:s404], handlers
  end


  def test_handle_status_missing
    assert_nil Foo.new.handle_status(404)
  end


  def test_handle_error
    handlers = []
    Foo.error{ handlers << :default }

    err = ArgumentError.new
    foo = Foo.new
    foo.handle_error(err)

    assert_equal [err], foo.env['gin.errors']
    assert_equal [:default], handlers
    assert_equal 500, foo.status
  end


  def test_all_errors_no_rescue_handler
    handlers = []
    Foo.all_errors{ handlers << :all }

    err = ArgumentError.new
    bar = Bar.new

    assert_raises ArgumentError do
      bar.handle_error err
    end

    assert_equal [err], bar.env['gin.errors']
    assert_equal [:all], handlers
    assert_equal 500, bar.status
  end


  def test_handle_error_all_errors
    handlers = []
    err = ArgumentError.new

    Foo.error{|e| raise "Unexpected Error" unless err == e; handlers << :default }
    Foo.all_errors{|e| raise "Unexpected Error" unless err == e; handlers << :all }

    foo = Foo.new
    foo.handle_error(err)

    assert_equal [err], foo.env['gin.errors']
    assert_equal [:default, :all], handlers
    assert_equal 500, foo.status
  end


  def test_handle_error_with_status
    Foo.error(Gin::NotFound){ "OOPS" }
    foo = Foo.new

    foo.status 200
    foo.handle_error(Gin::NotFound.new)
    assert_equal 404, foo.status

    foo.status 302
    foo.handle_error(Gin::NotFound.new)
    assert_equal 404, foo.status
  end


  def test_handle_error_preset_status
    Foo.error{ "OOPS" }
    foo = Foo.new

    foo.status(400)
    foo.handle_error(ArgumentError.new)
    assert_equal 400, foo.status

    foo.status(302)
    foo.handle_error(ArgumentError.new)
    assert_equal 500, foo.status

    foo.status(200)
    foo.handle_error(ArgumentError.new)
    assert_equal 500, foo.status
  end


  def test_handle_error_preset_status_with_status
    Foo.error(Gin::NotFound){ "OOPS" }
    foo = Foo.new
    foo.status(400)
    foo.handle_error(Gin::NotFound.new)

    assert_equal 404, foo.status
  end


  def test_handle_error_missing
    foo = Foo.new
    err = ArgumentError.new

    assert_raises ArgumentError do
      foo.handle_error(err)
    end

    assert_equal [err], foo.env['gin.errors']
    assert_equal 500, foo.status
  end
end
