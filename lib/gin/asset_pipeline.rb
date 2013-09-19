require 'sprockets'
require 'fileutils'

class Gin::AssetPipeline

  attr_accessor :logger
  attr_reader   :render_dir, :name, :asset_paths

  def initialize name, render_dir, asset_paths, &block
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
    self.name = name

    load_assets_version
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
    return false if @sprockets.paths == paths

    @listen_lock.write_sync do
      @sprockets.clear_paths
      paths.each{|path| @sprockets.append_path(path) }
    end

    true
  end


  def assets_version_file
    File.join(@render_dir, "#{@name}.assets.version")
  end


  def calculate_assets_version
    md5 = Digest::MD5.new
    globpaths = @asset_paths.map do |pa|
      pa.end_with?('/**/*') ? pa : File.join(pa, "**", "*")
    end

    filepaths = Dir.glob(globpaths)
    filepaths.uniq!

    filepaths.each do |path|
      if File.file?(path)
        md5.update path
        md5.update Digest::MD5.file(path).hexdigest
      end
    end

    md5.hexdigest
  end


  def load_assets_version
    filepath = assets_version_file
    @assets_version = File.file?(filepath) ? File.read(filepath).strip : nil
  end


  def update_assets_version
    @curr_assets_version ||= calculate_assets_version
    @assets_version = @curr_assets_version
    File.open(assets_version_file, "w"){|f| f.write(@assets_version) }
  end


  def assets_version_outdated?
    @curr_assets_version = calculate_assets_version
    @curr_assets_version != @assets_version
  end


  def name= new_name
    @listen_lock.write_sync do
      old_vfile = assets_version_file

      @name = new_name
      new_vfile = assets_version_file

      FileUtils.mv(old_vfile, new_vfile) if
        File.file?(old_vfile) && old_vfile != new_vfile
      @name
    end
  end


  def render_dir= new_dir
    new_dir = File.expand_path(new_dir)

    if !@render_dir || @render_dir != new_dir
      @listen_lock.write_sync do
        # TODO: instead of re-rendering everything, maybe move rendered assets?
        @flag_update = true
        @render_dir  = new_dir
        load_assets_version
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

  def render_all
    @render_lock.write_sync{ @rendering += 1 }

    unless assets_version_outdated?
      log "No assets to update. \
Delete the version file to force asset rendering:\n  #{assets_version_file}\n"
      return
    end

    start = Time.now

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

    log "Assets rendered in (#{(Time.now.to_f - start.to_f).round(3)} sec)"

    update_assets_version

  ensure
    @render_lock.write_sync do
      @rendering -= 1
      @rendering = 0 if @rendering < 0
      @flag_update = false
    end
  end


  def render path
    render_path = File.join(@render_dir, path)

    file_glob = render_path.sub(/(\.\w+)$/, '-*\1')
    file_name = Dir[file_glob].first

    asset = @sprockets[path]
    return unless asset

    digest = asset.digest[0..7]
    return if !asset || file_name && file_name.include?(digest)

    log "Rendering asset: #{path}"
    render_filename = file_glob.sub('*', digest)

    FileUtils.mkdir_p File.dirname(render_filename)
    File.open(render_filename, 'wb'){|f| f.write asset.source }

    File.delete(file_name) if file_name

    true
  end
end
