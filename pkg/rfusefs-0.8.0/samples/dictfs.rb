# dictfs.rb
#

require "rubygems"
require 'fusefs'
include FuseFS

require 'dict'

class DictFS < FuseFS::FuseDir
  def initialize
    @servers = ['dict.org','alt0.dict.org']
    @database = DICT::ALL_DATABASES
    @strategy = 'exact'
    @match_strategy = DICT::DEFAULT_MATCH_STRATEGY
    @port = DICT::DEFAULT_PORT

    @dict = DICT.new(@servers, @port, false, false)
    @dict.client("%s v%s" % ["Dictionary","1.0"])
  end
  def contents(path)
    # The 'readme' file
    ['readme']
  end
  def file?(path)
    base, rest = split_path(path)
    rest.nil? # DictFS doesn't have subdirs.
  end
  def read_file(path)
    word, rest = split_path(path)
    word.downcase!
    if word == "readme"
      return %Q[
DictFS: You may not see the files, but if you cat any file here, it will look
that file up on dict.org!
].lstrip
    end
    puts "Looking up #{word}"
    m = @dict.match(@database, @strategy, word)
    if m
      contents = []
      m.each do |db,words|
        words.each do |w|
          defs = @dict.define(db,w)
          str = []
          defs.each do |d|
            str << "Definition of '#{w}' (by #{d.description})"
            d.definition.each do |line|
              str << "  #{line.strip}"
            end
            contents << str.join("\n")
          end
        end
      end
      contents << ''
      contents.join("\n")
    else
      "No dictionary definitions found\n"
    end
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

  root = DictFS.new

  # Set the root FuseFS
  FuseFS.set_root(root)

  FuseFS.mount_under(dirname)

  FuseFS.run # This doesn't return until we're unmounted.
end
