require 'spec_helper'
require 'rfusefs'
require 'tmpdir'
require 'pathname'
require 'hello'

describe "Access Hello World sample from Ruby file operations" do
    let(:mountpoint) { Pathname.new(Dir.mktmpdir("rfusefs_sample")) }

	before(:all) do
		hello = HelloDir.new()
		FuseFS.mount(hello,mountpoint)
		#Give FUSE some time to get started 
		sleep(0.5)
	end
	
	after(:all) do
		FuseFS.unmount(mountpoint)
        sleep(0.5)
        FileUtils.rmdir(mountpoint)
	end
	
	it "should list expected root directory contents" do
		Dir.entries(mountpoint.to_s).should =~ [".","..","hello.txt"]
	end
	
	it "should output the expected sample contents" do
		(mountpoint + "hello.txt").read().should == "Hello, World!\n"
	end
end
