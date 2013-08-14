unless Time.now.respond_to?(:httpdate)

class Time
  def httpdate(date)
    if /\A\s*
        (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\x20
        (\d{2})\x20
        (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
        (\d{4})\x20
        (\d{2}):(\d{2}):(\d{2})\x20
        GMT
        \s*\z/x =~ date
      self.rfc2822(date)
    elsif /\A\s*
           (?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\x20
           (\d\d)-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d\d)\x20
           (\d\d):(\d\d):(\d\d)\x20
           GMT
           \s*\z/x =~ date
      year = $3.to_i
      if year < 50
        year += 2000
      else
        year += 1900
      end
      self.utc(year, $2, $1.to_i, $4.to_i, $5.to_i, $6.to_i)
    elsif /\A\s*
           (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\x20
           (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
           (\d\d|\x20\d)\x20
           (\d\d):(\d\d):(\d\d)\x20
           (\d{4})
           \s*\z/x =~ date
      self.utc($6.to_i, MonthValue[$1.upcase], $2.to_i,
               $3.to_i, $4.to_i, $5.to_i)
    else
      raise ArgumentError.new("not RFC 2616 compliant date: #{date.inspect}")
    end
  end
end
end
