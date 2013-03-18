class Gin::Router

  class PathArgumentError < Gin::Error; end

  class Mount
    DEFAULT_ACTION_MAP = {
      :index   => %w{get /},
      :show    => %w{get /:id},
      :new     => %w{get /new},
      :create  => %w{post /:id},
      :edit    => %w{get /:id/edit},
      :update  => %w{put /:id},
      :destroy => %w{delete /:id}
    }

    VERBS = %w{get post put delete head options trace}

    VERBS.each do |verb|
      define_method(verb){|action, *args| add(verb, action, *args)}
    end


    def initialize ctrl, base_path, sep="/", &block
      @sep       = sep
      @ctrl      = ctrl
      @routes    = []
      @actions   = []
      @base_path = base_path.split(@sep)

      instance_eval(&block) if block_given?
      defaults unless block_given?
    end


    # Create restful routes if they aren't taken already.
    def defaults default_verb=nil
      default_verb = (default_verb || 'get').to_s.downcase

      (@ctrl.actions - @actions).each do |action|
        verb, path = DEFAULT_ACTION_MAP[action]
        verb, path = [default_verb, "/#{action}"] if verb.nil?

        add(verb, action, path) unless verb.nil? ||
          @routes.any?{|(r,n,(c,a,p))| r == make_route(verb, path)[0] }
      end
    end


    def any action, path=nil
      VERBS.each{|verb| send verb, action, path}
    end


    def make_route verb, path
      param_keys = []
      route = [verb].concat @base_path
      route.concat path.split(@sep)
      route.delete_if{|part| part.empty?}

      route.map! do |part|
        if part[0] == ":"
          param_keys << part[1..-1]
          "%s"
        else
          part
        end
      end

      [route, param_keys]
    end


    def add verb, action, *args
      path = args.shift        if String === args[0]
      name = args.shift.to_sym if args[0]

      path ||= action.to_s
      name ||= :"#{action}_#{@ctrl.controller_name}"

      route, param_keys = make_route(verb, path)
      @routes << [route, name, [@ctrl, action, param_keys]]
      @actions << action.to_sym
    end


    def each_route &block
      @routes.each{|(route, name, value)| block.call(route, name, value) }
    end
  end


  class Node
    attr_accessor :value

    def initialize
      @children = {}
    end

    def [] key
      @children[key]
    end

    def add_child key, val=nil
      @children[key] ||= Node.new
      @children[key].value = val unless val.nil?
    end
  end


  def initialize separator="/" # :nodoc:
    @sep = separator
    @routes_tree = Node.new
    @routes_lookup = {}
  end


  ##
  # Add a Controller to the router with a base path.

  def add ctrl, base_path=nil, &block
    base_path ||= ctrl.controller_name

    mount = Mount.new(ctrl, base_path, @sep, &block)

    mount.each_route do |route_ary, name, val|
      curr_node = @routes_tree

      route_ary.each do |part|
        curr_node.add_child part
        curr_node = curr_node[part]
      end

      curr_node.value = val
      route = [route_ary[0], "/" << route_ary[1..-1].join(@sep), val[2]]

      @routes_lookup[name]      = route if name
      @routes_lookup[val[0..1]] = route
    end
  end


  ##
  # Check if a Controller and action combo has a route.

  def has_route? ctrl, action
    !!@routes_lookup[[ctrl, action]]
  end


  ##
  # Yield every Controller, action, route combination.

  def each_route &block
    @routes_lookup.each do |key,route|
      next unless Array === key
      block.call route, key[0], key[1]
    end
  end


  ##
  # Get the path to the given Controller and action combo or route name,
  # provided with the needed params. Routes with missing path params will raise
  # MissingParamError. Returns a String starting with "/".
  #
  #   path_to FooController, :show, :id => 123
  #   #=> "/foo/123"
  #
  #   path_to :show_foo, :id => 123
  #   #=> "/foo/123"

  def path_to *args
    key = Class === args[0] ? args.slice!(0..1) : args.shift
    verb, route, param_keys = @routes_lookup[key]
    raise PathArgumentError, "No route for #{Array(key).join("#")}" unless route

    params = (args.pop || {}).dup

    route = route.dup
    route = route % param_keys.map do |k|
      params.delete(k) || params.delete(k.to_sym) ||
        raise(PathArgumentError, "Missing param #{k}")
    end unless param_keys.empty?

    route << "?#{Gin.build_query(params)}" unless params.empty?

    route
  end


  ##
  # Takes a path and returns an array of 3 items:
  #   [controller_class, action_symbol, path_params_hash]
  # Returns nil if no match was found.

  def resources_for http_verb, path
    param_vals = []
    curr_node  = @routes_tree[http_verb.to_s.downcase]
    return unless curr_node

    path.scan(%r{/([^/]+|$)}) do |(key)|
      next if key.empty?

      if curr_node[key]
        curr_node = curr_node[key]

      elsif curr_node["%s"]
        param_vals << key
        curr_node = curr_node["%s"]

      else
        return
      end
    end

    return unless curr_node.value
    rsc = curr_node.value.dup

    rsc[-1] = param_vals.empty? ?
              Hash.new :
              rsc[-1].inject({}){|h, name| h[name] = param_vals.shift; h}

    rsc
  end
end
