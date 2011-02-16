require 'spec_helper'

describe FuseFS do
	
	before(:all) do
		module Kernel
			class << self
				alias_method :old_fork, :fork
				  
				def fork(*args,&block)
					0	
				end
			end
		end
		
		module Process
			class << self
				alias_method :old_kill, :kill
				
				def kill(*args)
					#do nothing.
				end
			end
		end
	end
	
	after(:all) do
		module Kernel
			class << self
				alias_method :fork, :old_fork
			end
		end
		
		module Process
			class << self
				alias_method :kill, :old_kill
			end
		end
	end
	
	describe "#mount" do
		it "mounts a fuse filesystem in a subprocess" do
			#actually we'll let the Cucumber tests handle this scenario.
		end
	end
	
	describe "#mounted?" do
		before(:each) do
			DapFS.mount("/myDapFS","")
		end
		it "returns true if fork has been called for a mountpoint" do
			DapFS.mounted?("/myDapFS").should be true
		end
			
		it "returns false if fork have never been called for a mountpoint" do
			DapFS.mounted?("/anotherDapFS").should be false
		end
	end
	
	describe "#unmount" do
		it "unmounts a previously mounted filesystem" do
			#also leave this to Cucumber
		end
		
		it "does nothing if the filesystem has never been mounted" do
			#and we don't really care about this anyway
		end
	end
	
end


