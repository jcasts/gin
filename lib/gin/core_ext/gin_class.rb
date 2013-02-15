module GinClass
  private

  def class_proxy_reader name, *names
    names.unshift name
    names.each do |n|
      define_method(n){ self.class.send n }
    end
  end
end
