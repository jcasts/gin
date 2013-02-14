class Gin::Router

  class Mount
    VERBS = %w{get post put delete head options trace}

    VERBS.each do |verb|
      define_method(verb){|action, path=nil| add verb, action, path}
    end

    def initialize ctrl, base_path, sep="/"
      @sep       = sep
      @ctrl      = ctrl
      @routes    = []
      @base_path = base_path.split(@sep)
    end


    def any action, path=nil
      VERBS.each{|verb| send verb, action, path}
    end


    def add verb, action, path=nil
      path ||= action.to_s
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

      @routes << [route, [@ctrl, action, param_keys]]
    end


    def each_route &block
      @routes.each{|(route, value)| block.call(route, value) }
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

  def add ctrl, base_path, &block
    mount = Mount.new ctrl, base_path, @sep
    mount.instance_eval(&block)

    mount.each_route do |route_ary, val|
      curr_node = @routes_tree

      route_ary.each do |part|
        curr_node.add_child part
        curr_node = curr_node[part]
      end

      curr_node.value = val
      @routes_lookup[val[0..1]] =
        [route_ary[0], "/" << route_ary[1..-1].join(@sep), val[2]]
    end
  end


  ##
  # Get the path to the given Controller and action combo, provided
  # with the needed params. Routes with missing path params will raise
  # MissingParamError. Returns a String starting with "/".

  def path_for ctrl, action, params={}
    verb, route, param_keys = @routes_lookup[[ctrl, action]]
    raise Gin::InvalidRouteError, "No route for #{ctrl}##{action}" unless route

    route = route % param_keys.map do |k|
      params[k] || params[k.to_sym] ||
        raise(Gin::MissingParamError, "Missing param #{k}")
    end unless param_keys.empty?

    route
  end


  ##
  # Takes a path and returns an array of 3 items:
  #   [controller_class, action_symbol, path_params_hash]
  # Returns nil if no match was found.

  def resources_for http_verb, path
    param_vals = []
    curr_node  = @routes_tree[http_verb.to_s.downcase]
    parts      = path.split(@sep)

    parts.each do |key|
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
