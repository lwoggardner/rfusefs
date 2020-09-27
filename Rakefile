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

task :default => ["spec","spec:fusefs"]
# vim: syntax=ruby

RELEASE_BRANCH = 'master'
desc 'Release RFuseFS Gem'
task :release,[:options] => %i(clobber default) do |_t,args|
  args.with_defaults(options: '--pretend')
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  raise "Cannot release from #{branch}, only master" unless branch == RELEASE_BRANCH
  Bundler.with_unbundled_env do
    raise "Tag failed" unless system({'RFUSE_RELEASE' => 'Y'},"gem tag -p #{args[:options]}".strip)
    raise "Bump failed" unless system("gem bump -v patch -p #{args[:options]}".strip)
  end
end
