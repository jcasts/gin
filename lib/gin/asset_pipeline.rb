require 'sprockets'
require 'fileutils'
require 'gin/asset_manifest'


class Gin::AssetPipeline

  attr_accessor :logger

  def initialize manifest_file, render_dir, asset_paths, sprockets, &block
    @rendering  = 0
    @logger     = $stderr
    @listen     = false
    @thread     = false
    @sprockets  = nil
    @flag_update = false

    @render_lock = Gin::RWLock.new
    @listen_lock = Gin::RWLock.new

    @manifest = Gin::AssetManifest.new(manifest_file, render_dir, asset_paths)

    setup_listener(asset_paths, sprockets, &block)
  end


  def setup_listener asset_paths=[], spr=nil, &block
    spr = Sprockets::Environment.new unless Sprockets::Environment === spr

    @manifest.asset_globs = asset_paths

    @manifest.source_dirs.each do |path|
      spr.append_path path
    end

    yield spr if block_given?

    @manifest.asset_globs |= spr.paths
    @sprockets = spr
  end


  def manifest_file
    @manifest.filepath
  end


  def manifest_file= new_file
    @manifest.filepath = new_file
  end


  def render_dir
    @manifest.render_dir
  end


  def render_dir= new_dir
    new_dir = File.expand_path(new_dir)

    if @manifest.render_dir != new_dir
      @listen_lock.write_sync do
        # TODO: instead of re-rendering everything, maybe move rendered assets?
        @flag_update = true
        @manifest.render_dir = new_dir
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
      render_all if outdated?
      sleep 0.2
    end
  end


  def listen?
    @listen_lock.read_sync{ @listen }
  end


  def stop
    @listen_lock.write_sync{ @listen = false }
  end


  def stop!
    stop
    @thread.join if @thread && @thread.alive?
  end


  def outdated?
    @flag_update || @manifest.outdated?
  end


  def update_sprockets
    paths = @manifest.source_dirs
    return if @sprockets.paths == paths

    @sprockets.clear_paths
    paths.each{|path| @sprockets.append_path(path) }
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
    while dir != self.render_dir && Dir[File.join(dir,'*')].empty?
      FileUtils.rm_r(dir)
      dir = File.dirname(dir)
    end
  end


  ##
  # Looks at all rendered, added, and modified assets and compiles those
  # out of date or missing.

  def render_all
    update_sprockets

    with_render_lock do
      sp_files = @sprockets.each_file.map(&:to_s).uniq

      # delete rendered files that aren't in the asset_dirs
      @manifest.assets.each do |asset_file, asset|
        valid_asset = sp_files.include?(asset_file)
        next if valid_asset

        target_file = asset.target_file
        remove_path target_file if target_file
        @manifest.delete(asset_file)
      end

      # render assets and update tree index
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

    ext = render_ext(asset)
    render_path = File.join(self.render_dir, asset.logical_path)

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


  private

  def render_ext asset
    path  = asset.pathname.to_s
    ctype = asset.content_type
    ctype == 'application/octet-stream' ?
     File.extname(path) : @sprockets.extension_for_mime_type(ctype)
  end
end
