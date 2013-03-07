module GinClass #:nodoc:
  private

  def class_proxy name, *names
    names.unshift name
    names.each do |n|
      define_method(n){|*args,&block| self.class.send(n,*args,&block) }
    end
  end
end
