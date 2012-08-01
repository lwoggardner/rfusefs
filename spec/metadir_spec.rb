require 'spec_helper'
require 'tmpdir'

describe FuseFS::MetaDir do
  
  context "in ruby" do
    
    before(:each) do
      @metadir = FuseFS::MetaDir.new()
      @metadir.mkdir("/test")
      @metadir.mkdir("/test/hello")
      @metadir.mkdir("/test/hello/emptydir")
      @metadir.write_to("/test/hello/hello.txt","Hello World!\n")
    end
    
    context "general directory methods" do
      it "should list directory contents" do
        @metadir.contents("/").should =~ [ "test" ]
        @metadir.contents("/test").should =~ [ "hello" ]
        @metadir.contents("/test/hello").should =~ ["hello.txt", "emptydir" ]
      end
      
      it "should indicate paths which are/are not directories" do
        @metadir.directory?("/test").should be_true
        @metadir.directory?("/test/hello").should be_true
        @metadir.directory?("/test/hello/hello.txt").should be_false
        @metadir.directory?("/nodir").should be_false
        @metadir.directory?("/test/nodir").should be_false
      end
      
      it "should indicate paths which are/are not files" do
        @metadir.file?("/test").should be_false
        @metadir.file?("/test/nodir").should be_false
        @metadir.file?("/test/hello").should be_false
        @metadir.file?("/test/hello/hello.txt").should be_true
      end
      
      it "should indicate the size of a file" do
        @metadir.size("/test/hello/hello.txt").should be "Hello World!\n".length
      end
    end
    
    context "with write access" do
      
      around(:each) do |example|
        FuseFS::RFuseFS.context(fuse_context(),&example)
      end
      
      before(:each) do
        FuseFS::reader_uid.should == Process.uid
        FuseFS::reader_gid.should == Process.gid
      end
      
      
      it "should allow directory creation" do
        @metadir.can_mkdir?("/test/otherdir").should be_true
      end
      
      it "should allow file creation and update" do
        @metadir.can_write?("/test/hello/newfile").should be_true
        @metadir.can_write?("/test/hello/hello.txt").should be_true
      end
      
      it "should read files" do
        @metadir.read_file("/test/hello/hello.txt").should == "Hello World!\n"
      end
      
      it "should update existing files" do
        @metadir.write_to("/test/hello/hello.txt","new contents")
        @metadir.read_file("/test/hello/hello.txt").should == "new contents"
      end
      
      it "should not allow deletion of non empty directories" do
        @metadir.can_rmdir?("/test/hello").should be_false
      end
      
      it "should delete directories" do
        @metadir.rmdir("/test/hello/emptydir")
        @metadir.contents("/test/hello").should =~ ["hello.txt"]
      end
      
      it "should allow and delete files" do
        @metadir.can_delete?("/test/hello/hello.txt").should be_true
        @metadir.delete("/test/hello/hello.txt")
        @metadir.contents("/test/hello").should =~ ["emptydir"]
      end
      
      it "should move directories at same level" do
        before = @metadir.contents("/test/hello")
        @metadir.rename("/test/hello","/test/moved").should be_true
        @metadir.directory?("/test/moved").should be_true
        @metadir.contents("/test/moved").should =~ before
        @metadir.read_file("/test/moved/hello.txt").should == "Hello World!\n"
      end

      it "should move directories between different paths" do
        @metadir.mkdir("/test/other")
        @metadir.mkdir("/test/other/more")
        before = @metadir.contents("/test/hello")
        @metadir.rename("/test/hello","/test/other/more/hello").should be_true
        @metadir.contents("/test/other/more/hello").should =~ before
        @metadir.read_file("/test/other/more/hello/hello.txt").should == "Hello World!\n"
      end

    end
    
    context "with readonly access" do
      around(:each) do |example|
        #Simulate a different userid..
        FuseFS::RFuseFS.context(fuse_context(-1,-1),&example)
      end
      
      before(:each) do
        FuseFS::reader_uid.should_not == Process.uid
        FuseFS::reader_gid.should_not == Process.gid
      end
      
      it "should not allow directory creation" do
        @metadir.can_mkdir?("/test/anydir").should be_false
        @metadir.can_mkdir?("/test/hello/otherdir").should be_false
      end
      
      it "should not allow file creation or write access" do
        @metadir.can_write?("/test/hello/hello.txt").should be_false
        @metadir.can_write?("/test/hello/newfile").should be_false
      end
      
      it "should not allow file deletion" do
        @metadir.can_delete?("/test/hello/hello.txt").should be_false
      end
      
      it "should not allow directory deletion" do
        @metadir.can_rmdir?("/test/emptydir").should be_false
      end
      
      it "should not allow directory renames" do
        @metadir.rename("/test/emptydir","/test/otherdir").should be_false
        #TODO and make sure it doesn't rename
      end

      it "should not allow file renames" do
        @metadir.rename("test/hello/hello.txt","test/hello.txt2").should be_false
        #TODO and make sure it doesn't rename
      end
    end
    
    context "with subdirectory containing another FuseFS" do
      around(:each) do |example|
        FuseFS::RFuseFS.context(fuse_context(),&example)
      end

      before(:each) do
        @fusefs = mock("mock_fusefs")
        @metadir.mkdir("/test")
        @metadir.mkdir("/test/fusefs",@fusefs)
      end

      api_methods = [:directory?, :file?, :contents, :executable?, :size, :times, :read_file, :can_write?,  :can_delete?, :delete, :can_mkdir?, :can_rmdir?, :rmdir, :touch, :raw_open, :raw_truncate, :raw_read, :raw_write, :raw_close]
      api_methods.each do |method|
          it "should pass on #{method}" do
             arity = FuseFS::FuseDir.instance_method(method).arity().abs - 1
             args = Array.new(arity) { |i| i }
             @fusefs.should_receive(method).with("/path/to/file",*args).and_return("anything")
             @metadir.send(method,"/test/fusefs/path/to/file",*args)
          end
      end
     
      it "should pass on :write_to" do
         @fusefs.should_receive(:write_to).with("/path/to/file","new contents\n")
         @metadir.write_to("/test/fusefs/path/to/file","new contents\n")
      end

      it "should pass on :mkdir" do
         @fusefs.should_receive(:mkdir).with("/path/to/file",nil).once().and_raise(ArgumentError)
         @fusefs.should_receive(:mkdir).with("/path/to/file").once().and_return("true")
         @metadir.mkdir("/test/fusefs/path/to/file")
      end

      it "should rename within same directory" do
        @fusefs.should_receive(:rename).with("/oldfile","/newfile")
        @metadir.rename("/test/fusefs/oldfile","/test/fusefs/newfile")
      end

      it "should pass rename down common directories" do
        @fusefs.should_receive(:rename).with("/path/to/file" ,"/new/path/to/file")
        @metadir.rename("/test/fusefs/path/to/file","/test/fusefs/new/path/to/file")
      end

      it "should rename across directories if from_path is a FuseFS object that accepts extended rename" do
        @fusefs.should_receive(:rename).with("/path/to/file","/nonfusepath",
                    an_instance_of(FuseFS::MetaDir)) do | myPath, extPath, extFS |
                        extFS.write_to(extPath,"look Mum, no hands!")
                    end

        @metadir.rename("/test/fusefs/path/to/file","/test/nonfusepath").should be_true
        @metadir.read_file("/test/nonfusepath").should == "look Mum, no hands!"
      end

      it "should quietly return false if from_path is a FuseFS object that does not accept extended rename" do
        @fusefs.should_receive(:rename).
            with("/path/to/file","/nonfusepath",an_instance_of(FuseFS::MetaDir)).
                and_raise(ArgumentError)
        @metadir.rename("/test/fusefs/path/to/file","/test/nonfusepath").should be_false

      end

      it "should not attempt rename file unless :can_write? the destination" do
        @fusefs.should_receive(:can_write?).with("/newpath/to/file").and_return(false)
        @metadir.write_to("/test/aFile","some contents")
        @metadir.rename("/test/aFile","/test/fusefs/newpath/to/file").should be_false
      end

      it "should not attempt rename directory unless :can_mkdir? the destination" do
        @fusefs.should_receive(:can_mkdir?).with("/newpath/to/dir").and_return(false)
        @metadir.mkdir("/test/aDir","some contents")
        @metadir.rename("/test/aDir","/test/fusefs/newpath/to/dir").should be_false
      end

    end
    
  end
  context "in a mounted FUSE filesystem" do
	before(:all) do
		tmpdir = Pathname.new(Dir.tmpdir) + "rfusefs"
		tmpdir.mkdir unless tmpdir.directory?
		@mountpoint = tmpdir + "metadir_spec"
        puts "#{@mountpoint}"
		@mountpoint.mkdir unless @mountpoint.directory?
		@metadir = FuseFS::MetaDir.new()
        @metadir.mkdir("/test")
        @metadir.write_to("/test/hello.txt","Hello World!\n")
		FuseFS.mount(@metadir,@mountpoint)
        @testdir = (@mountpoint + "test")
        @testfile = (@testdir + "hello.txt")
		#Give FUSE some time to get started 
		sleep(1)
	end
	
	after(:all) do
		FuseFS.unmount(@mountpoint)
	end
	
    it "should list directory contents" do
		@testdir.entries().should =~ pathnames(".","..","hello.txt")
    end

    it "should read files" do
        @testfile.file?.should be_true
		@testfile.read().should == "Hello World!\n"
    end

    it "should create directories" do
        newdir = @testdir + "newdir"
        newdir.mkdir()
        newdir.directory?.should be_true
        @testdir.entries().should =~ pathnames(".","..","hello.txt","newdir")
    end

    it "should create files" do
        newfile = @testdir + "newfile"
        newfile.open("w") do |file|
            file << "A new file\n"
        end
        newfile.read.should == "A new file\n"
    end

    it "should move directories" do
        fromdir = @testdir + "fromdir"
        fromdir.mkdir()
        subfile = fromdir + "afile"
        subfile.open("w") do |file|
           file << "testfile\n"
        end

        movedir = (@mountpoint + "movedir")
        movedir.directory?.should be_false
        fromdir.rename(movedir)
        movedir.directory?.should be_true
        
        subfile = movedir + "afile"
        subfile.file?.should be_true
        subfile.read.should == "testfile\n"
    end

    it "should move files" do
        movefile = (@mountpoint + "moved.txt")
        movefile.file?.should be_false
        @testfile.should be_true
        @testfile.rename(movefile)
        movefile.read.should == "Hello World!\n"
    end

  end
  
end
