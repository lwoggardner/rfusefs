require "rubygems"
require 'rfusefs'

include FuseFS

root = MetaDir.new

# if (ARGV.size != 1)
#   puts "Usage: #{$0} <directory>"
#   exit
# end

dirname = ARGV.shift

unless File.directory?(dirname)
  puts "Usage: #{$0} <directory>"
  exit
end

class DirLink
  def initialize(dir)
    File.directory?(dir) or raise ArgumentError, "DirLink.initialize expects a valid directory!"
    @base = dir
  end
  def directory?(path)
    File.directory?(File.join(@base,path))
  end
  def file?(path)
    File.file?(File.join(@base,path))
  end
  def contents(path)
    fn = File.join(@base,path)
    Dir.entries(fn).map { |file|
      file = file.sub(/^#{fn}\/?/,'')
      if ['..','.'].include?(file)
        nil
      else
        file
      end
    }.compact.sort
  end
  def read_file(path)
    fn = File.join(@base,path)
    if File.file?(fn)
      IO.read(fn)
    else
      'No such file'
    end
  end
end
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

root.mkdir("/#{ENV['USER']}",DirLink.new(ENV['HOME']))

FuseFS.start(dirname,root,'nolocalcaches', *ARGV)
