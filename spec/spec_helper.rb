SPEC_DIR = File.dirname(__FILE__)
lib_path = File.expand_path("#{SPEC_DIR}/../samples")
puts lib_path
$LOAD_PATH.unshift lib_path unless $LOAD_PATH.include?(lib_path)


require 'rfusefs'
require 'fusefs/metadir'
require 'fcntl'
require 'tmpdir'
require 'pathname'
require 'fileutils'

module RFuseFSHelper

    def pathnames(*args)
        args.collect {|x| Pathname.new(x) }
    end
    
	def permissions(mode)
        return (mode & 07777)
	end
	
	def filetype(mode)
	    return (mode & RFuse::Stat::S_IFMT)
	end

    FuseContext = Struct.new(:uid,:gid)    
    def fuse_context(uid=Process.uid,gid=Process.gid)
       FuseContext.new(uid,gid)
    end

    def pathmap(real_file,mapped_path)
       File.open(real_file.to_s,"w") do |f|
            f << mapped_path
       end
    end

    def mktmpdir(name)
		tmpdir = Pathname.new(Dir.tmpdir) + "rfusefs"
        tmpdir = tmpdir + name
        FileUtils.mkdir_p(tmpdir.to_s) unless tmpdir.directory?
        tmpdir
    end
end

include RFuseFSHelper
