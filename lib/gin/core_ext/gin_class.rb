module GinClass #:nodoc:
  private

  def opt_reader name, *names
    names.unshift name
    names.each do |n|
      define_method(n){ @options[n] }
    end
  end


  def class_rproxy name, *names
    names.unshift name
    names.each do |n|
      define_method(n){ self.class.send(n) }
    end
  end


  def class_proxy name, *names
    names.unshift name
    names.each do |n|
      define_method(n){|*args,&block| self.class.send(n,*args,&block) }
    end
  end
end
