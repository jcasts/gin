require 'cgi'

unless CGI.escapeHTML("'") == "&#39;"

class CGI #:nodoc:
  class << self
    alias_method :__escapeHTML, :escapeHTML
  end

  def self.escapeHTML str
    __escapeHTML(str).gsub("'", "&#39;")
  end
end

end
