require 'rfusefs'
require 'tmpdir'
require 'pathname'
require 'samples/hello'

describe "Access Hello World sample from Ruby file operations" do
	before(:all) do
		tmpdir = Pathname.new(Dir.tmpdir) + "rfusefs"
		tmpdir.mkdir unless tmpdir.directory?
		@mountpoint = tmpdir + "sample_spec"
		@mountpoint.mkdir unless @mountpoint.directory?
		hello = HelloDir.new()
		FuseFS.mount(@mountpoint,hello)
		#Give FUSE some time to get started 
		sleep(1)
	end
	
	after(:all) do
		FuseFS.unmount(@mountpoint)
	end
	
	it "should list expected root directory contents" do
		Dir.entries(@mountpoint.to_s).should =~ [".","..","hello.txt"]
	end
	
	it "should output the expected sample contents" do
		(@mountpoint + "hello.txt").read().should == "Hello, World!\n"
	end
end
