##
# The Gin::Mountable module provides an interface to mount any type of object
# to a Gin::App route.

module Gin::Mountable

  def verify_mount! #:nodoc:
    controller_name.to_str

    test_action = actions[0]

    test_route = default_route_for(test_action)
    test_route[0].to_str
    test_route[1].to_str

    route_name_for(test_action).to_proc

    display_name.to_str
    display_name(test_action).to_str

    true
  end


  ##
  # The actions available on this Mountable object.
  # Actions can be of any object type.
  #
  # Must return an Array of actions. Must be overloaded.
  #   UserController.actions
  #   #=> [:show, :delete, :list, :update]

  def actions
    raise NoMethodError,
      "The `#{__method__}' method must be defined on #{self} and return an\
Array of available actions for the Router to map to."
  end


  ##
  # The String representing the controller.
  #
  # Must return a String. Must be overloaded.
  #   UserController.controller_name
  #   #=> 'user'

  def controller_name
    raise NoMethodError,
      "The `#{__method__}' method must be defined on #{self} and return a\
String representing the controller name."
  end


  ##
  # Should return a 2 item Array with the HTTP verb and request path (local to
  # the controller) to use for a given action.
  #
  # Must return a 2 item Array of Strings. Must be overloaded.
  #   UserController.default_route_for :show
  #   #=> ['GET', '/:id']

  def default_route_for action
    raise NoMethodError,
      "The `#{__method__}' method must be defined on #{self} and return a\
2 item Array with the HTTP verb and local path: ['GET', '/users/:id']"
  end


  ##
  # Creates a route name used to identify a given route. Used by helper methods.
  #
  # Must return a Symbol, or nil. Must be overloaded.
  #   UserController.route_name_for :show
  #   #=> :show_user

  def route_name_for action
    raise NoMethodError,
      "The `#{__method__}' method must be defined on #{self} and return a\
Symbol representing the route name: :show_user"
  end


  ##
  # Creates a display name for the Controller (and optional action).
  # Used for logging and error messages.
  #
  # Must return a String. Must be overloaded.
  #   UserController.display_name :show
  #   #=> "UserController#show"

  def display_name action=nil
    raise NoMethodError,
      "The `#{__method__}' method must be defined on #{self} and return a\
String for display purposes"
  end
end
