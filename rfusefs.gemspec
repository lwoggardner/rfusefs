# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rfusefs/version"

Gem::Specification.new do |s|
  s.name        = "rfusefs"
  s.version     = RFuseFS::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Grant Gardner"]
  s.email       = ["grant@lastweekend.com.au"]
  s.homepage    = "http://rubygems.org/gems/rfusefs"
  s.summary     = %q{Filesystem in Ruby Userspace}
  s.description = %q{A more Ruby like way to write FUSE filesystems - inspired by (compatible with) FuseFS, implemented over RFuse}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,spec-fusefs}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.has_rdoc = 'yard'
  s_extra_rdoc_files = 'History.rdoc'

  s.add_dependency("rfuse", "~> 1.1.0.RC0")
  s.add_development_dependency("rake")
  s.add_development_dependency("rspec","~> 2")
  s.add_development_dependency("yard")
  s.add_development_dependency("redcarpet")
  s.add_development_dependency("sqlite3")
  s.add_development_dependency("sys-filesystem")
  s.add_development_dependency("ffi-xattr", ">= 0.1.1")
end
