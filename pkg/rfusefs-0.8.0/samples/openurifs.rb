# openurifs.rb
#

require "rubygems"
require 'fusefs'
include FuseFS

require 'open-uri'

class OpenUriFS < FuseFS::FuseDir
  def contents(path)
    # The 'readme' file
    []
  end
  def directory?(path)
    uri = scan_path(path)
    fn = uri.pop
    return true if fn =~ /\.(com|org|net|us|de|jp|ru|uk|biz|info)$/
    return true if fn =~ /^\d+\.\d+\.\d+\.\d+$/
    ! (fn =~ /\./) # Does the last item doesn't contain a '.' ?
  end
  def file?(path)
    !directory?(path)
  end
  def read_file(path)
    proto, rest = split_path(path)
    uri = "#{proto}://#{rest}"
    open(uri).read
  end
end

if (File.basename($0) == File.basename(__FILE__))
  if (ARGV.size != 1)
    puts "Usage: #{$0} <directory>"
    exit
  end

  dirname = ARGV.shift

  unless File.directory?(dirname)
    puts "Usage: #{dirname} is not a directory."
    exit
  end

  root = OpenUriFS.new

  # Set the root FuseFS
  FuseFS.set_root(root)

  FuseFS.mount_under(dirname)

  FuseFS.run # This doesn't return until we're unmounted.
end
