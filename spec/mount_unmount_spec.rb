require 'spec_helper'
require 'rfusefs'
require 'tmpdir'
require 'pathname'

describe "a mounted FuseFS" do
    let(:mountpoint) { Pathname.new(Dir.mktmpdir("rfusefs_mount_unmount")) }

    after(:each) { FileUtils.rmdir mountpoint }

    it "should get mounted and unmounted callbacks" do
        mock_fs = FuseFS::FuseDir.new()
        mock_fs.should_receive(:mounted)
        mock_fs.should_receive(:unmounted)

        t = Thread.new { sleep 0.5 ; puts "exiting" ; FuseFS.exit }
        FuseFS.start(mock_fs,mountpoint)
        t.join
    end
end

