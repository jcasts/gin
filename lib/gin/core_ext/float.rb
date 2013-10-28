if Float.instance_method(:round).arity == 0
class Float
  undef round
  def round ndigits=0
    num, dec = self.to_s.split(".")
    num = "#{num}.#{dec[0,ndigits]}".sub(/\.$/, "")
    Float num
  end
end
end
