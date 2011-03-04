#Pathmapper is hard to test because it is difficult to mock Dir/Pathname/File etc...
require "spec_helper"
require "fusefs/pathmapper"

describe FuseFS::PathMapperFS do
  before(:all) do 
	   @tmpdir = mktmpdir("pathmapper")
       #create directory
       pathmap(@tmpdir + "hello.txt","/textfiles/hello")
       pathmap(@tmpdir + "mysong.mp3","/artist/album/mysong.mp3")
       pathmap(@tmpdir + "apicture.jpeg","/pictures/201103/apicture.jpg")
       @pathmapFS = FuseFS::PathMapperFS.create(@tmpdir) do |file|
            File.file?(file) ? IO.read(file.to_s) : nil
       end
  end

  context "in ruby" do
   
    context "standard mapping" do
       
        it "should map files and directories" do
            @pathmapFS.directory?("/").should be_true
            @pathmapFS.directory?("/textfiles").should be_true
            @pathmapFS.directory?("/pictures/201103").should be_true
            @pathmapFS.file?("/textfiles/hello").should be_true
            @pathmapFS.file?("/artist/album/mysong.mp3").should be_true
        end
            
        it "should list the mapped contents of directories" do
            @pathmapFS.contents("/").should =~ [ "textfiles","artist","pictures" ]
            @pathmapFS.contents("/artist").should =~ [ "album" ]
            @pathmapFS.contents("/textfiles").should =~ [ "hello" ]
        end

        it "should report the size of a file" do
            @pathmapFS.size("/textfiles/hello").should == 16
        end

        it "should report the atime,mtime and ctime of the mapped file" do
            atime,mtime,ctime = @pathmapFS.times("/pictures/201103/apicture.jpg")
            picture = @tmpdir + "apicture.jpeg"
            atime.should == picture.atime()
            mtime.should == picture.mtime()
            ctime.should == picture.ctime()
        end
    end

    context "writing to a pathmapped FS" 
    context "using raw access" 

    context "a real Fuse mounted filesystem" do
        before(:all) do
		    @mountpoint = Pathname.new(Dir.tmpdir) + "rfusefs-pathmapper"
		    @mountpoint.mkdir unless @mountpoint.directory?
            @pathmapFS.use_raw_file_access = true
            FuseFS.mount(@mountpoint,@pathmapFS)
            sleep(1)
        end

        it "should map files and directories" do
            (@mountpoint + "textfiles").directory?.should be_true
            (@mountpoint + "pictures/201103").directory?.should be_true
            (@mountpoint + "textfiles/hello").file?.should be_true
            (@mountpoint + "artist/album/mysong.mp3").file?.should be_true
        end

        it "should list the mapped contents of directories" do
           (@mountpoint + "textfiles").entries.should =~ pathnames(".","..","hello")
        end

        it "should represent the stat information of the underlying files" do
            hellopath=(@mountpoint + "textfiles/hello")
            realpath=(@tmpdir + "hello.txt")
            mappedstat = hellopath.stat
            realstat = realpath.stat
            mappedstat.size.should == realstat.size
            mappedstat.atime.should == realstat.atime 
            mappedstat.mtime.should == realstat.mtime
            mappedstat.ctime.should == realstat.ctime
        end

        it "should read the files" do
            hellopath = (@mountpoint + "textfiles/hello")
            hellopath.read.should == "/textfiles/hello"
            hellopath.open do |f|
                f.seek(2)
                f.read(3).should == "ext"
            end
            hellopath.sysopen do |f|
                f.sysseek(1)
                f.sysread(3).should == "tex"
            end
        end


        after(:all) do
            FuseFS.unmount(@mountpoint)
        end

    end


  
  end
  
  after(:all) do
    FileUtils.rm_rf(@tmpdir.to_s)
  end

 
end
