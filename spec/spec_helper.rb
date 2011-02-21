require 'rfusefs'
require 'fcntl'

module RFuseFSHelper

    def pathnames(*args)
        args.collect {|x| Pathname.new(x) }
    end
    
	def permissions(mode)
        return (mode & 07777)
	end
	
	def filetype(mode)
	    return (mode & FuseFS::Stat::S_IFMT)
	end

    FuseContext = Struct.new(:uid,:gid)    
    def fuse_context(uid=Process.uid,gid=Process.gid)
       FuseContext.new(uid,gid)
    end
end

include RFuseFSHelper
