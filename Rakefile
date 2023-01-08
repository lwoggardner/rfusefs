# -*- ruby -*-
require 'yard'
require 'rspec/core/rake_task'
require 'rake/clean'

CLOBBER.include [ "pkg/","doc/" ]

desc "Generate YARD docs"
YARD::Rake::YardocTask.new

RSpec::Core::RakeTask.new(:spec)

desc "FuseFS compatibility specs"
RSpec::Core::RakeTask.new("spec:fusefs") do |t|
  t.pattern = 'spec-fusefs/**/*_spec.rb'
end

task :default => ['version',"spec","spec:fusefs"]

require_relative 'lib/rfusefs/gem_version'
FFI::Libfuse::GemHelper.install_tasks(main_branch: RFuseFS::MAIN_BRANCH, version: RFuseFS::VERSION)
# vim: syntax=ruby

