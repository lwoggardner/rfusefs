require 'spec_helper'
require 'rfusefs'
require 'tmpdir'
require 'pathname'
require 'hello'

describe "Access Hello World sample from Ruby file operations" do

	before(:all) do
		mountpoint  = Pathname.new(Dir.mktmpdir("rfusefs_sample"))
		hello = HelloDir.new()
		FuseFS.mount(hello,mountpoint)
		#Give FUSE some time to get started
		sleep(0.5)
		@mountpoint = mountpoint
	end

	after(:all) do
		mountpoint = @mountpoint
		FuseFS.unmount(mountpoint)
    FileUtils.rmdir(mountpoint)
	end
	let(:mountpoint) { @mountpoint }

	it "should list expected root directory contents" do
		expect(Dir.entries(mountpoint.to_s)).to match_array([".","..","hello.txt"])
	end

	it "should output the expected sample contents" do
		expect((mountpoint + "hello.txt").read()).to eq("Hello, World!\n")
    puts "Done!!"
	end
end
