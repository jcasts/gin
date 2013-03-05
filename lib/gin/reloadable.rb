module Gin::Reloadable
  extend GinClass

  def self.included klass
    klass.extend ClassMethods
  end


  class_proxy :auto_reload


  module ClassMethods
    def reloadables
      @reloadables ||= {}
    end


    def auto_reload val=nil
      @auto_reload = val unless val.nil?
      @auto_reload
    end


    def erase_dependencies!
      reloadables.each do |key, (path, files, consts)|
        erase! files, consts
      end
      true
    end


    def erase! files, consts, parent=nil
      parent ||= Object
      files.each{|f| $LOADED_FEATURES.delete f }
      clear_constants parent, consts
    end


    def clear_constants parent, names=nil
      names ||= parent.constants

      names.each do |name|
        const = parent.const_get(name)
        next unless const

        if Class === const
          next unless parent == Object || const.name =~ /(^|::)#{parent.name}::/
          clear_constants const
          parent.send(:remove_const, name)
        else
          parent.send(:remove_const, name) rescue nil
        end
      end
    end


    def without_warnings &block
      warn_level = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = warn_level
    end


    def track_require file
      old_consts   = Object.constants
      old_features = $LOADED_FEATURES.dup

      filepath = Gin.find_loadpath file

      if !reloadables[filepath]
        success = Object.send(:require, file)

      else reloadables[filepath]
        without_warnings{
          success = Object.send(:require, file)
        }
      end

      reloadables[filepath] = [
        file,
        $LOADED_FEATURES - old_features,
        Object.constants - old_consts
      ] if success
      success
    end


    def require file
      if auto_reload
        track_require file

      else
        super file
      end
    end
  end
end
