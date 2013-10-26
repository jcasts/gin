require 'sprockets'
require 'fileutils'
require 'gin/asset_manifest'


# TODO: Need a place to keep track of asset dirs in sprockets and gin, and when
# globs match different dirs than previously found.
#       Need a place to convert source-asset name to rendered-asset name.

class Gin::AssetPipeline

  attr_accessor :logger
  attr_reader   :render_dir, :asset_paths

  def initialize manifest_file, render_dir, asset_paths, &block
    @rendering  = 0
    @logger     = $stderr
    @listen     = false
    @thread     = false
    @last_mtime = Time.now
    @render_dir = nil
    @sprockets  = nil
    @name       = nil
    @flag_update = false
    @asset_paths = nil

    @render_lock = Gin::RWLock.new
    @listen_lock = Gin::RWLock.new

    @render_dir = render_dir

    @manifest = Gin::AssetManifest.new(manifest_file, asset_paths)

    setup_listener(asset_paths, &block)
  end


  def setup_listener asset_paths=[], &block
    spr = Sprockets::Environment.new

    Dir.glob(asset_paths).each do |path|
      spr.append_path path
    end

    @asset_paths = asset_paths

    yield spr if block_given?

    return @sprockets = spr if !@sprockets

    @listen_lock.write_sync do
      # Prevent re-rendering all assets
      cache = @sprockets.instance_variable_get("@assets")
      spr.instance_variable_set("@assets", cache)
      @flag_update ||= spr.paths != @sprockets.paths
      @sprockets = spr
    end
  end


  def asset_dir_updated?
    paths = Dir.glob(@asset_paths).map{|pa| pa[-1] == ?/ ? pa[0..-2] : pa }
    return false if @sprockets.paths == @sprockets.paths | paths

    @listen_lock.write_sync do
      @sprockets.clear_paths
      paths.each{|path| @sprockets.append_path(path) }
    end

    true
  end


  def manifest_file
    @manifest.filepath
  end


  def manifest_file= new_file
    @manifest.filepath = new_file
  end


  def render_dir= new_dir
    new_dir = File.expand_path(new_dir)

    if !@render_dir || @render_dir != new_dir
      @listen_lock.write_sync do
        # TODO: instead of re-rendering everything, maybe move rendered assets?
        @flag_update = true
        @render_dir  = new_dir
      end
    end
  end


  def log str
    @logger << "#{str}\n"
  end


  ##
  # Returns true if in the middle of rendering, otherwise false.

  def rendering?
    @render_lock.read_sync{ @rendering != 0 || @flag_update }
  end


  def listen
    stop if listen?

    @thread = Thread.new do
      listen!
    end

    @thread.abort_on_exception = true
  end


  def listen!
    @listen_lock.write_sync{ @listen = true }

    while listen? do
      @listen_lock.read_sync do
        if @flag_update || asset_dir_updated?
          render_all
          @last_mtime = Time.now
          next
        end

        @sprockets.paths.each do |dir|
          next unless File.exist?(dir)
          mtime = File.mtime(dir) rescue 0
          if mtime > @last_mtime
            @last_mtime = mtime
            render_all
            break
          end
        end
      end

      sleep 0.2
    end
  end


  def listen?
    @listen_lock.read_sync{ @listen }
  end


  def stop
    @listen_lock.write_sync{ @listen = false }
    @thread.join if @thread && @thread.alive?
  end


  def local_path_for path
    path = path.sub(@render_dir,'')
    path.sub!(/^\//, '')
    path.sub!(/-[0-9a-f*]+(\.\w+)$/i, '\1')
  end


  def with_render_lock &block
    @render_lock.write_sync{ @rendering += 1 }
    start = Time.now
    block.call

    log "Assets rendered in (#{(Time.now.to_f - start.to_f).round(3)} sec)"

  ensure
    @render_lock.write_sync do
      @rendering -= 1
      @rendering = 0 if @rendering < 0
      @flag_update = false
    end
  end


  def remove_path path
    log "Deleting asset: #{path}"
    File.delete(path)

    dir = File.dirname(path)
    while dir != @render_dir && Dir[File.join(dir,'*')].empty?
      FileUtils.rm_r(dir)
      dir = File.dirname(dir)
    end
  end


  ##
  # Looks at all rendered, added, and modified assets and compiles those
  # out of date or missing.

  def _render_all
    with_render_lock do
      dir_glob = File.join(@render_dir, "**", "*")

      Dir[dir_glob].each do |path|
        next unless File.file?(path)
        next unless local_path = local_path_for(path)
        valid_asset = @sprockets.resolve(local_path) rescue false
        remove_path path if !valid_asset
      end

      @sprockets.each_logical_path do |path|
        render path
      end
    end
  end


  def render_all
    with_render_lock do
      # delete rendered files that aren't in the asset_dirs
      sp_files = @sprockets.each_file.map(&:to_s).uniq
      @manifest.assets.each do |asset_file, asset|
        valid_asset = sp_files.include?(asset_file)
        next if valid_asset

        target_file = asset.target_file
        remove_path target_file if target_file
        @manifest.delete(asset_file)
      end

      # update tree index
      sp_files.each do |asset_file|
        next unless @manifest.asset_outdated?(asset_file)
        sp_asset = @sprockets[asset_file] # First time render

        if target_file = render(asset_file)
          @manifest.stage asset_file, target_file,
            sp_asset.dependencies.map{|d| d.pathname.to_s }
        end
      end

      @manifest.commit!

      # save cache to disk
      @manifest.save_file!
    end
  end


  def render path
    asset = @sprockets[path]
    return unless asset

    ctype = asset.content_type
    ext = ctype == "application/octet-stream" ?
            File.extname(path) :
            @sprockets.extension_for_mime_type(ctype)

    render_path = File.join(@render_dir, asset.logical_path)

    file_glob = render_path.sub(/(\.\w+)$/, "-*#{ext}")
    file_name = Dir[file_glob].first

    digest = asset.digest[0..7]
    return file_name if file_name && file_name.include?(digest)

    log "Rendering asset: #{path}"
    render_filename = file_glob.sub('*', digest)

    FileUtils.mkdir_p File.dirname(render_filename)
    File.open(render_filename, 'wb'){|f| f.write asset.source }

    File.delete(file_name) if file_name

    return render_filename
  end
end
