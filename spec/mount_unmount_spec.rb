require 'spec_helper'
require 'rfusefs'
require 'tmpdir'
require 'pathname'

describe "a mounted FuseFS" do
    let(:mountpoint) { Pathname.new(Dir.mktmpdir("rfusefs_mount_unmount")) }

    after(:each) { FileUtils.rmdir mountpoint }

    it "should get mounted and unmounted callbacks" do
        mock_fs = FuseFS::FuseDir.new()
        expect(mock_fs).to receive(:mounted)
        expect(mock_fs).to receive(:unmounted)

        t = Thread.new { sleep 2.0 ; puts "exiting" ; FuseFS.exit }
        FuseFS.start(mock_fs,mountpoint)
        t.join
    end
end

