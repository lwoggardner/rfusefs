# -*- ruby -*-

require 'rubygems'
require 'hoe'

# Hoe.plugin :compiler
# Hoe.plugin :gem_prelude_sucks
# Hoe.plugin :inline
# Hoe.plugin :racc
# Hoe.plugin :rubyforge
Hoe.plugin :yard
Hoe.plugin :git

Hoe.spec 'rfusefs' do
  developer('Grant Gardner', 'grant@lastweekend.com.au')
end

#We need to run the fusefs compatibility specs separately
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec-fusefs/**/*_spec.rb'
end

# vim: syntax=ruby
