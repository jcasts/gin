require "test/test_helper"

class ControllerTest < Test::Unit::TestCase

  def test_supports_filters
    assert Gin::Controller.ancestors.include?(Gin::Filterable)
  end
end
