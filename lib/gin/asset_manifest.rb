require 'yaml'
require 'digest/md5'

class Gin::AssetManifest

  class Asset

    attr_reader :path, :mtime, :digest, :dependencies
    attr_accessor :target_file

    def initialize path, opts={}
      @path   = path
      @rtime  = opts[:rtime]  || Time.now
      @mtime  = opts[:mtime]  || File.mtime(path)
      @digest = opts[:digest] || Digest::MD5.file(path).hexdigest
      @target_file = opts[:target_file]
      @dependencies = opts[:dependencies] || []
    end


    def update!
      return unless File.file?(@path)
      @rtime  = Time.now
      @mtime  = File.mtime(@path)
      @digest = Digest::MD5.file(@path).hexdigest
    end


    def outdated?
      return true if !File.file?(@path)
      return true if @target_file && !File.file?(@target_file)
      return @mtime != File.mtime(@path) if @rtime - @mtime > 0
      @digest != Digest::MD5.file(@path).hexdigest
    end


    def to_hash
      hash = {
        :target_file => @target_file,
        :rtime  => @rtime,
        :mtime  => @mtime,
        :digest => @digest }

      hash[:dependencies] = @dependencies.dup unless @dependencies.empty?

      hash
    end
  end


  attr_reader :assets, :filepath
  attr_accessor :render_dir, :asset_globs


  def initialize filepath, render_dir, asset_globs
    @staged = []
    @assets = {}
    @filepath = filepath
    @render_dir = render_dir
    @asset_globs = asset_globs

    load_file! if File.file?(@filepath)
  end


  def set asset_file, target_file, dependencies=[]
    squash_similar_targets(target_file)

    asset = @assets[asset_file] =
      Asset.new(asset_file, :target_file => target_file)

    Array(dependencies).each do |path|
      @assets[path] ||= Asset.new(path)
      asset.dependencies << path
    end
  end


  def squash_similar_targets target_file
    matcher = Regexp.escape( target_file.sub(/-\w+\.(\w+)$/, '') )
    matcher = Regexp.new "#{matcher}-\\w+\\.#{$1}"

    @assets.each do |name, asset|
      if asset.target_file && matcher =~ asset.target_file
        asset.target_file = nil
      end
    end
  end


  def stage asset_file, target_file, dependencies=[]
    @staged << [asset_file, target_file, dependencies]
  end


  def delete asset_file
    @assets.delete asset_file.to_s
  end


  def commit!
    until @staged.empty?
      set(*@staged.shift)
    end
  end


  def outdated?
    source_changed? || @assets.keys.any?{|f| asset_outdated?(f) }
  end


  def asset_outdated? asset_file, checked=[]
    # Check for circular dependencies
    return false if checked.include?(asset_file)
    checked << asset_file

    asset = @assets[asset_file]
    return true if !asset ||
      asset.target_file && !asset.target_file.start_with?(@render_dir) ||
      asset.outdated?

    asset.dependencies.any? do |path|
      return true if asset_outdated?(path, checked)
    end
  end


  def source_changed?
    source_files.sort != @assets.keys.sort
  end


  def source_files
    globs = @asset_globs.map{|gl|
              (gl =~ /\.(\*|\w+)$/) ? gl : File.join(gl, '**', '*') }

    Dir.glob(globs).reject{|path| !File.file?(path) }.uniq
  end


  def source_dirs
    Dir.glob(@asset_globs).map{|pa| pa[-1] == ?/ ? pa[0..-2] : pa }.uniq
  end


  def to_hash
    assets_hash = {}

    @assets.each do |path, asset|
      assets_hash[path] = asset.to_hash
    end

    assets_hash
  end


  def filepath= new_file
    FileUtils.mv(@filepath, new_file) if
      @filepath && new_file != @filepath && File.file?(@filepath)
    @filepath = new_file
  end


  def save_file!
    File.open(@filepath, 'w'){|f| f.write self.to_hash.to_yaml }
  end


  def load_file!
    yaml = YAML.load_file(@filepath)
    @assets.clear

    yaml.each do |path, info|
      @assets[path] = Asset.new path, info
    end
  end
end
