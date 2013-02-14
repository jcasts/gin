require 'cgi'

class CGI
  class << self
    alias_method :__escapeHTML, :escapeHTML
  end

  def self.escapeHTML str
    __escapeHTML(str).gsub!("'", "&#39;")
  end
end
