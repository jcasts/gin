# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugin :gemspec

Hoe.spec 'gin' do
  developer('Jeremie Castagna', 'yaksnrainbows@gmail.com')
  self.readme_file      = "README.rdoc"
  self.history_file     = "History.rdoc"
  self.extra_rdoc_files = FileList['*.rdoc']

  self.extra_deps << ['rack',            '~>1.1']
  self.extra_deps << ['rack-protection', '~>1.0']
  self.extra_deps << ['tilt',            '~>1.4']

  self.extra_dev_deps << ['nokogiri', '~>1.5.9']
  self.extra_dev_deps << ['plist',    '~>3.1.0']
  self.extra_dev_deps << ['bson',     '~>1.9.0']
end

# vim: syntax=ruby
