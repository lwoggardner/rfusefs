# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require_relative 'lib/rfusefs/gem_version'

Gem::Specification.new do |s|
  s.name        = "rfusefs"
  s.version     = RFuseFS::GEM_VERSION
  s.license     = 'MIT'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Grant Gardner"]
  s.email       = ["grant@lastweekend.com.au"]
  s.homepage    = "http://rubygems.org/gems/rfusefs"
  s.summary     = %q{Filesystem in Ruby Userspace}
  s.description = %q{A more Ruby like way to write FUSE filesystems - inspired by (compatible with) FuseFS, implemented over RFuse}

  s.files         = Dir['lib/**/*.rb','*.md','LICENSE','.yardopts']
  s.require_paths = ["lib"]

  s.required_ruby_version = '>= 2.7'

  s.add_dependency("rfuse", "~> 2.0")
  s.add_development_dependency("rake")
  s.add_development_dependency("rspec","~> 3")
  s.add_development_dependency("yard")
  s.add_development_dependency("redcarpet")
  s.add_development_dependency("sqlite3")
  s.add_development_dependency("sys-filesystem")
  s.add_development_dependency("ffi-xattr", ">= 0.1.1")
end
