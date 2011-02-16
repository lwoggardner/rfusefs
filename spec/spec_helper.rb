require 'rfusefs'
require 'fcntl'

module RFuseFSHelper
	def permissions(mode)
		return (mode & 07777)
	end
	
	def filetype(mode)
		return (mode & FuseFS::Stat::S_IFMT)
	end
end

include RFuseFSHelper

