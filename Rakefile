# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.spec 'gin' do
  developer('Jeremie Castagna', 'yaksnrainbows@gmail.com')
  self.readme_file      = "README.rdoc"
  self.history_file     = "History.rdoc"
  self.extra_rdoc_files = FileList['*.rdoc']

  self.extra_deps << ['rack',            '~>1.5.2']
  self.extra_deps << ['rack-protection', '~>1.3.2']
  self.extra_deps << ['activesupport',   '>=2.3.17']

  self.extra_dev_deps << ['mocha', '~>0.13.2']
end

# vim: syntax=ruby
