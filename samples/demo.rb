require "rubygems"
require 'rfusefs'
require 'fusefs/metadir'
require 'fusefs/dirlink'

include FuseFS

root = MetaDir.new

class Counter
  def initialize
    @counter = 0
  end
  def to_s
    @counter += 1
    @counter.to_s + "\n"
  end
  def size
    @counter.to_s.size
  end
end

class Randwords
  def initialize(*ary)
    @ary = ary.flatten
  end
  def to_s
    @ary[rand(@ary.size)].to_s + "\n"
  end
  def size
    @size ||= @ary.map{|v| v.size}.max
  end
end

root.write_to('/hello',"Hello, World!\n")

progress = '.'

root.write_to('/progress',progress)

Thread.new do
  20.times do
    sleep 5
    progress << '.'
  end
end

root.write_to('/counter',Counter.new)
root.write_to('/color',Randwords.new('red','blue','green','purple','yellow','bistre','burnt sienna','jade'))
root.write_to('/animal',Randwords.new('duck','dog','cat','duck billed platypus','silly fella'))

root.mkdir("/#{ENV['USER']}",FuseFS::DirLink.new(ENV['HOME']))

unless ARGV.length > 0 && File.directory?(ARGV[0])
  puts "Usage: #{$0} <mountpoint> <mountoptions>"
  exit
end

FuseFS.start(root, *ARGV)
