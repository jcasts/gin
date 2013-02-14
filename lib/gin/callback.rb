module Gin::Callback

  def callbacks
    @callbacks ||= {}
  end


  def handles? callback
    !!callbacks[callback]
  end


  def trigger callback, target=nil
    return unless callbacks[callback]
    target ||= self
    target.instance_eval(&callbacks[callback])
  end


  def callback key, *more, &block
    return unless block_given?
    more.unshift(key).each{|k| callbacks[k] = block }
  end
end
