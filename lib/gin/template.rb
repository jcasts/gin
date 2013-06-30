gem 'tilt', '>=1.4.1'
require 'tilt'
require 'gin/cache'

class Gin::App

  on_setup do
    @template_engines = {}
    @templates = Gin::Cache.new
    @options[:layout] = :layout
  end

  on_init do
    @options[:layouts_dir] ||= File.join(root_dir, 'layouts')
    @options[:views_dir]   ||= File.join(root_dir, 'views')
  end


  ##
  # Get or set the layout name. Layout file location is assumed to be in
  # the views_dir. If the views dir has a controller wildcard '*', the layout
  # is assumed to be one level above the controller-specific directory.
  #
  # Defaults to :layout.

  def self.layout name=nil
    @options[:layout] = name if name
    @options[:layout]
  end


  ##
  # Get or set the directory for view layouts.
  # Defaults to the "<root_dir>/layouts".

  def self.layouts_dir dir=nil
    @options[:layouts_dir] = dir if dir
    @options[:layouts_dir]
  end


  ##
  # Get or set the path to the views directory.
  # The wildcard '*' will be replaced by the controller name.
  #
  # Defaults to "<root_dir>/views"

  def self.views_dir dir=nil
    @options[:views_dir] = dir if dir
    @options[:views_dir]
  end


  ##
  # Get or set the default templating engine to use for various
  # file extensions:
  #   template_engines 'markdown' => Tilt::MarukuTemplate,
  #                    'md' => Tilt::BlueClothTemplate
  #
  # Template engines must support the following usecase:
  #   scope = self
  #   local_variables = {:foo => "value"}
  #   block = lambda{ "BLOCK RENDERED HERE" }
  #
  #   engine = Engine.new(filepath)
  #   engine.render(scope, local_variables, &block)
  #   #=> "Something something foo=value BLOCK RENDERED HERE something more"

  def self.template_engines more=nil
    @template_engines.merge!(more) if more
    @template_engines
  end


  ##
  # Returns the tilt template for the given template name.
  # Returns nil if no template file is found.
  #   template_for 'user/show'
  #   #=> <Tilt::ERBTemplate @file="views/user/show.erb" ...>
  #
  #   template_for 'user/show.haml'
  #   #=> <Tilt::HamlTemplate @file="views/user/show.haml" ...>
  #
  #   template_for 'non-existant'
  #   #=> nil

  def self.template_for path, engine=nil
    t_key = [path, engine]
    return @templates[t_key] if @templates[t_key]

    tplt_klass = engine if Class === engine
    tplt_klass = template_engine_for(engine) if engine && !tplt_klass

    if File.file?(path)
      tplt_klass ||= template_engine_for(path)
      return @templates[t_key] = tplt_klass.new(path) if tplt_klass
    end

    file = Dir["#{path}.*"].find do |file|
      tplt_klass ?
        template_engines_for(file).include?(tplt_klass) :
          tplt_klass = template_engine_for(file)
    end

    @templates[t_key] = tplt_klass.new(file) if file && tplt_klass
  end


  ##
  # Array of template engine classes for a given file or file extension.

  def self.template_engines_for file_or_ext
    extname = File.extname(file_or_ext)[1..-1] || file_or_ext
    Array(template_engines[extname]).concat(Array(Tilt.mappings[extname]))
  end


  ##
  # Template engines class for a given file or file extension.

  def self.template_engine_for file_or_ext
    extname = File.extname(file_or_ext)[1..-1] || file_or_ext
    template_engines[extname] || Tilt[extname]
  end

  opt_reader :layout, :layouts_dir, :views_dir
  class_proxy :template_for
end


class Gin::Controller

  ##
  # Get or set a layout for a given controller.
  # Value can be a symbol or filepath.
  # Layout file is expected to be in the Gin::App.layout_dir directory
  # Defaults to the parent class layout, or Gin::App.layout.

  def self.layout name=nil
    @layout = name if name
    return @layout if @layout
    return self.superclass.layout if self.superclass.respond_to?(:layout)
  end


  ##
  # Value of the layout to use for rendering.
  # See also Gin::Controller.layout and Gin::App.layout.

  def layout
    self.class.layout || @app.layout
  end


  ##
  # Returns the path to where the template is expected to be.
  #   template_path :foo
  #   #=> "<views_dir>/foo"
  #
  #   template_path "sub/foo"
  #   #=> "<views_dir>/sub/foo"
  #
  #   template_path "sub/foo", :layout
  #   #=> "<layouts_dir>/sub/foo"
  #
  #   template_path "/other/foo"
  #   #=> "<root_dir>/other/foo"

  def template_path template, is_layout=false
    dir = if template[0] == ?/
            @app.root_dir
          elsif is_layout
            @app.layouts_dir
          else
            @app.views_dir
          end

    dir = dir.gsub('*', controller_name)
    File.join(dir, template.to_s)
  end


  ##
  # Render a template with the given view template.
  # Options supported:
  # :locals:: Hash - local variables used in template
  # :layout:: Symbol/String - a custom layout to use
  # :scope:: Object - The scope in which to render the template: default self
  # :content_type:: Symbol/String - Content-Type header to set
  # :engine:: String - Tilt rendering engine to use
  # :layout_engine:: String - Tilt layout rendering engine to use
  #
  # The template argument may be a String or a Symbol. By default the
  # template location will be looked for under Gin::App.views_dir, but
  # the directory may be specified as any directory under Gin::App.root_dir
  # by using the '/' prefix:
  #
  #   view 'foo/template'
  #   #=> Renders file "<views_dir>/foo/template"
  #
  #   view '/foo/template'
  #   #=> Renders file "<root_dir>/foo/template"

  def view template, opts={}, &block
    content_type(opts.delete(:content_type)) if opts[:content_type]

    scope    = opts[:scope]  || self
    locals   = opts[:locals] || {}
    r_layout = opts[:layout] || layout

    template   = template_path(template)
    v_template = @app.template_for template, controller_name, opts[:engine]
    raise TemplateMissing, "No such template `#{template}'" unless v_template

    if r_layout
      r_layout   = template_path(r_layout, true)
      r_template = @app.template_for r_layout, nil, opts[:layout_engine]
      raise TemplateMissing, "No such layout `#{r_layout}'" unless r_template
      r_template.render(scope, locals){
        v_template.render(scope, locals, &block) }
    else
      v_template.render(scope, locals, &block)
    end
  end
end
