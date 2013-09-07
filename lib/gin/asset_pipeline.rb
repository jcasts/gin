require 'sprockets'
require 'fileutils'

class Gin::AssetPipeline

  attr_accessor :logger
  attr_reader   :render_dir

  def initialize render_dir, asset_paths, &block
    @rendering  = 0
    @logger     = $stderr
    @listen     = false
    @thread     = false
    @last_mtime = Time.now
    @render_dir = nil
    @sprockets  = nil
    @flag_update  = false

    @render_lock = Gin::RWLock.new
    @listen_lock = Gin::RWLock.new

    self.render_dir = render_dir
    setup_listener(asset_paths, &block)
  end


  def setup_listener asset_paths=[], &block
    spr = Sprockets::Environment.new

    asset_paths.each do |glob|
      glob = File.join(glob, '')
      Dir[glob].each do |path|
        spr.append_path path
      end
    end

    yield spr if block_given?

    return @sprockets = spr if !@sprockets

    @listen_lock.write_sync do
      @flag_update ||= spr.paths != @sprockets.paths
      @sprockets = spr
    end
  end


  def render_dir= new_dir
    new_dir = File.expand_path(new_dir)

    if @render_dir && @render_dir != new_dir
      @listen_lock.write_sync do
        @flag_update = true
        @render_dir  = new_dir
      end
    else
      @render_dir = new_dir
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
        render_all and next if @flag_update

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


  def logical_path_for path
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
    start = Time.now

    dir_glob = File.join(@render_dir, "**", "*")

    Dir[dir_glob].each do |path|
      next unless File.file?(path)
      logical_path = logical_path_for(path)
      remove_path path if !@sprockets[logical_path]
    end

    @sprockets.each_logical_path do |path|
      render path
    end

    log "Assets rendered in (#{(Time.now.to_f - start.to_f).round(3)} sec)"

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
    return if !asset || file_name && file_name.include?(asset.digest)

    log "Rendering asset: #{path}"
    render_filename = file_glob.sub('*', asset.digest)

    FileUtils.mkdir_p File.dirname(render_filename)
    File.open(render_filename, 'wb'){|f| f.write asset.source }

    File.delete(file_name) if file_name

    true
  end
end
