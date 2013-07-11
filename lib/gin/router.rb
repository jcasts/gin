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


    def initialize ctrl, base_path, &block
      @ctrl      = ctrl
      @routes    = []
      @actions   = []
      @base_path = base_path

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
          @routes.any?{|route| route === [verb, path] }
      end
    end


    def any action, path=nil
      VERBS.each{|verb| send verb, action, path}
    end


    def add verb, action, *args
      path = args.shift        if String === args[0]
      name = args.shift.to_sym if args[0]

      path ||= action.to_s
      name ||= :"#{action}_#{@ctrl.controller_name}"

      path = File.join(@base_path, path)
      target = [@ctrl, action]

      route = Route.new(verb, path, target, name)
      @routes << route
      @actions << action.to_sym
    end


    def each_route &block
      @routes.each{|(route, name, value)| block.call(route, name, value) }
    end
  end


  class Route
    attr_reader :param_keys, :match_keys, :path, :target, :name

    SEP = "/"
    VAR_MATCHER = /:(\w+)/
    PARAM_MATCHER = "(.*?)"


    def initialize verb, path, target, name
      @target = target
      @name   = name
      build verb, path
    end


    def to_path params={}
      rendered_path = @path.dup
      rendered_path = rendered_path % @param_keys.map do |k|
        params.delete(k) || params.delete(k.to_sym) ||
          raise(PathArgumentError, "Missing param #{k}")
      end unless @param_keys.empty?

      rendered_path << "?#{Gin.build_query(params)}" unless params.empty?
      rendered_path
    end


    def === other
      @route_id == other
    end


    private

    def build verb, path
      @path = ""
      @param_keys = []
      @match_keys = []
      @route_id = [verb, path]

      parts = [verb].concat path.split(SEP)

      parts.each_with_index do |p, i|
        next if p.empty?

        part = Regexp.escape(p).gsub!(VAR_MATCHER) do
          @param_keys << $1
          PARAM_MATCHER
        end

        if part == PARAM_MATCHER
          part = "%s"
        elsif $1
          part = /^#{part}$/
        else
          part = p
        end

        @path << "#{SEP}#{p.gsub(VAR_MATCHER, "%s")}" if i > 0
        @match_keys << part
      end
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

    def match key
      @children.keys.each do |k|
        next unless Regexp === k
        m = k.match key
        return [@children[k], m[1..-1]] if m
      end
      nil
    end

    def add_child key
      @children[key] ||= Node.new
    end
  end


  def initialize
    @routes_tree = Node.new
    @routes_lookup = {}
  end


  ##
  # Add a Controller to the router with a base path.

  def add ctrl, base_path=nil, &block
    base_path ||= ctrl.controller_name

    mount = Mount.new(ctrl, base_path, &block)

    mount.each_route do |route|
      curr_node = @routes_tree

      route.match_keys.each do |part|
        curr_node.add_child part
        curr_node = curr_node[part]
      end

      curr_node.value = route
      @routes_lookup[route.name]   = route if route.name
      @routes_lookup[route.target] = route
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
    route = @routes_lookup[key]
    raise PathArgumentError, "No route for #{Array(key).join("#")}" unless route

    params = (args.pop || {}).dup

    route.to_path(params)
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

      elsif child_and_matches = curr_node.match(key)
        param_vals.concat child_and_matches[1]
        curr_node = child_and_matches[0]

      else
        return
      end
    end

    return unless curr_node.value
    route = curr_node.value

    path_params = param_vals.empty? ?
      {} : route.param_keys.inject({}){|h, name| h[name] = param_vals.shift; h}

    [*route.target, path_params]
  end
end
