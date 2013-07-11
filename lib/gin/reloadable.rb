module Gin::Reloadable #:nodoc:
  extend GinClass

  def self.included klass
    klass.extend ClassMethods
  end


  module ClassMethods #:nodoc:
    def reloadables
      @reloadables ||= {}
    end


    def erase_dependencies!
      reloadables.each do |key, (_, files, consts)|
        erase! files, consts
      end
      true
    end


    def erase! files, consts, parent=nil
      parent ||= ::Object
      files.each{|f| $LOADED_FEATURES.delete f }
      clear_constants parent, consts
    end


    def clear_constants root, names=nil
      each_constant(root, names) do |name, const, parent|
        if Module === const || !gin_constants[const.object_id]
          parent.send(:remove_const, name) rescue nil
        end
      end
    end


    def gin_constants
      return @gin_constants if defined?(@gin_constants) && @gin_constants
      @gin_constants = {Gin.object_id => ::Gin}

      each_constant(Gin) do |name, const, _|
        @gin_constants[const.object_id] = const
      end

      @gin_constants
    end


    def each_constant parent, names=nil, &block
      names ||= parent.constants
      names.each do |name|
        const = parent.const_get(name)
        next unless const

        if ::Module === const
          next unless parent == ::Object || const.name =~ /(^|::)#{parent.name}::/
          each_constant(const, &block)
        end

        block.call name, const, parent
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
      old_consts   = ::Object.constants
      old_features = $LOADED_FEATURES.dup

      filepath = Gin.find_loadpath file

      if !reloadables[filepath]
        success = ::Object.send(:require, file)

      else reloadables[filepath]
        without_warnings{
          success = ::Object.send(:require, file)
        }
      end

      reloadables[filepath] = [
        file,
        $LOADED_FEATURES - old_features,
        ::Object.constants - old_consts
      ] if success

      success
    end
  end
end
