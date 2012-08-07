# -*- ruby -*-
require "bundler/gem_tasks"
require 'yard'
require 'rspec/core/rake_task'

YARD::Rake::YardocTask.new do |t|
        # Need this because YardocTask does not read the gemspec
        t.files   = ['lib/**/*.rb', '-','History.rdoc']   # optional
end

RSpec::Core::RakeTask.new(:spec)

desc "FuseFS compatibility specs"
RSpec::Core::RakeTask.new("spec:fusefs") do |t|
  t.pattern = 'spec-fusefs/**/*_spec.rb'
end

# vim: syntax=ruby
