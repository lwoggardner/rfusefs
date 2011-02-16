# yamlfs.rb
#

require "rubygems"
require 'fusefs'
include FuseFS

require 'yaml'

class YAMLFS < FuseFS::FuseDir
  def initialize(filename)
    @filename = filename
    begin
      @fs = YAML.load(IO.read(filename))
    rescue Exception
      @fs = Hash.new()
    end
  end
  def save
    File.open(@filename,'w') do |fout|
      fout.puts(YAML.dump(@fs))
    end
  end
  def contents(path)
    items = scan_path(path)
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.keys.sort
  end
  def directory?(path)
    items = scan_path(path)
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.is_a?(Hash)
  end
  def file?(path)
    items = scan_path(path)
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.is_a?(String)
  end
  def touch(path)
    puts "#{path} has been pushed like a button!"
  end

  # File reading
  def read_file(path)
    items = scan_path(path)
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.to_s
  end
  
  def size(path)
    read_file(path).size
  end

  # File writing
  def can_write?(path)
    items = scan_path(path)
    name = items.pop # Last is the filename.
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.is_a?(Hash)
  rescue Exception => er
    puts "Error! #{er}"
  end
  def write_to(path,body)
    items = scan_path(path)
    name = items.pop # Last is the filename.
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node[name] = body
    self.save
  rescue Exception => er
    puts "Error! #{er}"
  end

  # Delete a file
  def can_delete?(path)
    items = scan_path(path)
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.is_a?(String)
  rescue Exception => er
    puts "Error! #{er}"
  end
  def delete(path)
    items = scan_path(path)
    name = items.pop # Last is the filename.
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.delete(name)
    self.save
  rescue Exception => er
    puts "Error! #{er}"
  end

  # mkdirs
  def can_mkdir?(path)
    items = scan_path(path)
    name = items.pop # Last is the filename.
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.is_a?(Hash)
  rescue Exception => er
    puts "Error! #{er}"
  end
  def mkdir(path)
    items = scan_path(path)
    name = items.pop # Last is the filename.
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node[name] = Hash.new
    self.save
  end

  # rmdir
  def can_rmdir?(path)
    items = scan_path(path)
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.is_a?(Hash) && node.empty?
  end
  def rmdir(path)
    items = scan_path(path)
    name = items.pop # Last is the filename.
    node = items.inject(@fs) do |node,item|
      item ? node[item] : node
    end
    node.delete(name)
    self.save
  end
end

if (File.basename($0) == File.basename(__FILE__))
  if (ARGV.size < 2)
    puts "Usage: #{$0} <directory> <yamlfile> <options>"
    exit
  end

  dirname, yamlfile = ARGV.shift, ARGV.shift

  unless File.directory?(dirname)
    puts "Usage: #{dirname} is not a directory."
    exit
  end

  root = YAMLFS.new(yamlfile)

  # Set the root FuseFS
  FuseFS.set_root(root)

  FuseFS.mount_under(dirname, *ARGV)

  FuseFS.run # This doesn't return until we're unmounted.
end
