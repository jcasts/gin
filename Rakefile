# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.spec 'gin' do
  developer('Jeremie Castagna', 'yaksnrainbows@gmail.com')
  self.readme_file      = "README.rdoc"
  self.history_file     = "History.rdoc"
  self.extra_rdoc_files = FileList['*.rdoc']

  self.extra_deps << ['rack',            '~>1.1']
  self.extra_deps << ['rack-protection', '~>1.0']
  self.extra_deps << ['tilt',            '~>1.4']

  self.extra_dev_deps << ['nokogiri',  '~>1.5.9']
  self.extra_dev_deps << ['plist',     '~>3.1.0']
  self.extra_dev_deps << ['bson',      '~>1.9.0']
  self.extra_dev_deps << ['ruby-path', '~>1.0.2']
  self.extra_dev_deps << ['sprockets', '~>2.10.0']
  self.extra_dev_deps << ['uglifier',  '~>1.4.0']
  self.extra_dev_deps << ['sass',      '~>3.2.10']
end

# vim: syntax=ruby
