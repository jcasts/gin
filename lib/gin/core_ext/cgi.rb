require 'cgi'

unless RUBY_VERSION >= "2.0"

class CGI #:nodoc:
  class << self
    alias_method :__escapeHTML, :escapeHTML
  end

  def self.escapeHTML str
    __escapeHTML(str).gsub!("'", "&#39;")
  end
end

end
