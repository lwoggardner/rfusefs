#Pathmapper is hard to test because it is difficult to mock Dir/Pathname/File etc...
require "spec_helper"
require "fusefs/pathmapper"
require 'tmpdir'
require 'pathname'

class PMFixture
    attr_reader :tmpdir

    def initialize()
        @tmpdir = Pathname.new(Dir.mktmpdir("rfusefs_pathmapper"))
        pathmap(@tmpdir + "hello.txt","/textfiles/hello")
        pathmap(@tmpdir + "mysong.mp3","/artist/album/mysong.mp3")
        pathmap(@tmpdir + "apicture.jpeg","/pictures/201103/apicture.jpg")
    end

    def pathmap(real_file,mapped_path)
        File.open(real_file.to_s,"w") do |f|
            f << mapped_path
        end
    end

    def fs
        @fs ||= FuseFS::PathMapperFS.create(@tmpdir) do |file|
            File.file?(file) ? IO.read(file.to_s) : nil
        end
    end

    def mount()
        return @mountpoint if @mountpoint
        @mountpoint = Pathname.new(Dir.mktmpdir("rfusefs_pathmapper_mnt"))
        FuseFS.mount(fs,@mountpoint)
        sleep(0.5) 
        @mountpoint
    end

    def cleanup
        if @mountpoint
            FuseFS.unmount(@mountpoint) 
            sleep(0.5)
            FileUtils.rmdir(@mountpoint)
        end
        FileUtils.rm_r(@tmpdir)
    end
end


describe FuseFS::PathMapperFS do
    before(:each) do 
        @fixture = PMFixture.new
        @tmpdir = @fixture.tmpdir
        @pathmapFS = @fixture.fs
    end

    after(:each) do
        @fixture.cleanup
    end

    context "fusefs api" do

        it "maps files and directories" do
            @pathmapFS.directory?("/").should be_true
            @pathmapFS.directory?("/textfiles").should be_true
            @pathmapFS.directory?("/pictures/201103").should be_true
            @pathmapFS.file?("/textfiles/hello").should be_true
            @pathmapFS.directory?("/textfiles/hello").should be_false
            @pathmapFS.file?("/artist/album/mysong.mp3").should be_true
            @pathmapFS.directory?("/artist/album/mysong.mp3").should be_false
            @pathmapFS.file?("/some/unknown/path").should be_false
            @pathmapFS.directory?("/some/unknown/path").should be_false
        end

        it "lists the mapped contents of directories" do
            @pathmapFS.contents("/").should =~ [ "textfiles","artist","pictures" ]
            @pathmapFS.contents("/artist").should =~ [ "album" ]
            @pathmapFS.contents("/textfiles").should =~ [ "hello" ]
        end

        it "reports the size of a file" do
            @pathmapFS.size("/textfiles/hello").should == 16
        end

        it "reads the contents of a file" do
            @pathmapFS.read_file("/textfiles/hello").should == "/textfiles/hello"
        end

        it "does not allow writes" do
            @pathmapFS.can_write?("/textfiles/hello").should be_false
        end

        it "reports the atime,mtime and ctime of the mapped file" do
            atime,mtime,ctime = @pathmapFS.times("/pictures/201103/apicture.jpg")
            picture = @tmpdir + "apicture.jpeg"
            atime.should == picture.atime()
            mtime.should == picture.mtime()
            ctime.should == picture.ctime()
        end

        it "reports filesystem statistics"

        context "writing to a pathmapped FS" do
            before(:each) do
                @pathmapFS.allow_write=true
                @pathmapFS.write_to("textfiles/hello","updated content")
            end

            it "updates the contents of the real file" do
                hello_path = @tmpdir + "hello.txt"
                hello_path.read.should == "updated content"
            end

            it "updates the contents of the mapped file" do
                @pathmapFS.read_file("textfiles/hello").should == "updated content"
            end

            it "changes the reported file size" do
                @pathmapFS.size("textfiles/hello").should == 15
            end

            it "changes the filesystem statistics"
        end

    end

    context "a real Fuse mounted filesystem" do
        before(:each) do
            @pathmapFS.allow_write=true
            @mountpoint = @fixture.mount
        end

        it "maps files and directories" do
            (@mountpoint + "textfiles").directory?.should be_true
            (@mountpoint + "textfiles/hello").file?.should be_true
        end

        it "lists the mapped contents of directories" do
            (@mountpoint + "textfiles").entries.should =~ pathnames(".","..","hello")
        end

        it "represents the stat information of the underlying files" do
            hellopath=(@mountpoint + "textfiles/hello")
            realpath=(@tmpdir + "hello.txt")
            mappedstat = hellopath.stat
            realstat = realpath.stat
            mappedstat.size.should == realstat.size
            mappedstat.atime.should == realstat.atime 
            mappedstat.mtime.should == realstat.mtime
            mappedstat.ctime.should == realstat.ctime
        end

        it "reads the files" do
            hellopath= @mountpoint + "textfiles/hello"
            hellopath.read.should == "/textfiles/hello"
        end

        it "writes the files" do
            hellopath= @mountpoint + "textfiles/hello"
            real_path = @tmpdir + "hello.txt"
            hellopath.open("w") do |f|
                f.print "updated content"
            end 
            hellopath.read.should == "updated content"
            real_path.read.should == "updated content"
        end
    end

    context "a real Fuse mount with raw file access" do

        before(:each) do
            @pathmapFS.use_raw_file_access = true
            @pathmapFS.allow_write = true
            @mountpoint = @fixture.mount
        end

        it "reads files" do
            hello_path = (@mountpoint + "textfiles/hello")
            hello_path.open do |f|
                f.seek(2)
                f.read(3).should == "ext"
            end

            hello_path.sysopen do |f|
                f.sysseek(1)
                f.sysread(3).should == "tex"
            end
        end

        it "writes files" do
            hello_path = (@mountpoint + "textfiles/hello")
            real_path = @tmpdir + "hello.txt"
            hello_path.open("r+") do |f|
                f.sysseek(2)
                f.syswrite("zzz")
                f.sysseek(0)
                f.sysread(6).should == "/tzzzf"
            end 

            real_path.read.should == "/tzzzfiles/hello"   
        end

    end
end
