class Rack::CommonLogger
  alias log_without_check log unless method_defined? :log_without_check

  def log env, *args
    log_without_check(env, *args) unless env[Gin::Constants::GIN_TIMESTAMP]
  end
end
