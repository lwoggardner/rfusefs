# -*- ruby -*-
require 'rubygems'
require 'hoe'

Hoe.plugin :yard
Hoe.plugin :git

Hoe.spec 'rfusefs' do
  self.readme_file="README.rdoc"
  developer('Grant Gardner', 'grant@lastweekend.com.au')
  extra_deps << [ 'rfuse' , '>= 0.6.0' ]
end

desc "FuseFS compatibility specs"
RSpec::Core::RakeTask.new("spec:fusefs") do |t|
  t.pattern = 'spec-fusefs/**/*_spec.rb'
end

# vim: syntax=ruby
