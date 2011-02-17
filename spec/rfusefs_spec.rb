require 'spec_helper'

describe FuseFS do
  TEST_FILE = "/aPath/aFile" 
  TEST_DIR = "/aPath"
  ROOT_PATH = "/"
  Struct.new("FuseFileInfo",:flags,:fh)
  
  before(:each) do
    
    @mock_context = mock("rfuse context")
    @mock_context.stub!(:gid).and_return("222")
    @mock_context.stub!(:uid).and_return("333")
  end
  
  describe "an empty FuseFS object" do
    before(:each) do
      @fuse = FuseFS::RFuseFSAPI.new(Object.new())
    end
    
    it "should return an appropriate Stat for the root directory" do
      stat = @fuse.getattr(@mock_context,ROOT_PATH)
      stat.should respond_to(:dev)
      (stat.mode & FuseFS::Stat::S_IFDIR).should_not == 0
      (stat.mode & FuseFS::Stat::S_IFREG).should == 0
      permissions(stat.mode).should == 0555
    end
    
    it "should have an empty root directory" do
      filler = mock("entries_filler")
      filler.should_receive(:push).with(".",nil,0)
      filler.should_receive(:push).with("..",nil,0)
      @fuse.readdir(@mock_context,"/",filler,nil,nil)
    end
    
    it "should raise ENOENT for other paths" do
      lambda { @fuse.getattr(@mock_context,"/somepath") }.should raise_error(Errno::ENOENT)
    end
    
    it "should not allow new files or directories" do
      lambda { @fuse.mknod(@mock_context,"/afile",0100644,0) }.should raise_error(Errno::EACCES)
      lambda { @fuse.mkdir(@mock_context,"/adir",0040555) }.should raise_error(Errno::EACCES)
    end
  end
  
  describe "a FuseFS filesystem" do
    before(:each) do
      @mock_fuse = mock("FuseFS")
      @fuse = FuseFS::RFuseFSAPI.new(@mock_fuse)
    end
    
    describe :readdir do
      before(:each) do
        @mock_fuse.should_receive(:contents).with("/apath").and_return(["afile"])
      end
      
      it "should add  . and .. to the results of :contents when listing a directory" do
        filler = mock("entries_filler")
        filler.should_receive(:push).with(".",nil,0)
        filler.should_receive(:push).with("..",nil,0)
        filler.should_receive(:push).with("afile",nil,0)
        @fuse.readdir(@mock_context,"/apath",filler,nil,nil)
      end
      
    end
    
    describe :getattr do
      
      #Root directory is special (ish) so we need to run these specs twice.
      [ROOT_PATH,TEST_DIR].each do |dir|
        
        context "of a directory #{ dir }" do
          
          before(:each) do
            @mock_fuse.stub!(:file?).and_return(false)
            @mock_fuse.should_receive(:directory?).with(dir).at_most(:once).and_return(true)
            @checkfile =  (dir == "/" ? "" : dir ) + FuseFS::RFuseFS::CHECK_FILE
          end
          
          it "should return a Stat like object representing a directory" do
            @mock_fuse.should_receive(:can_write?).with(@checkfile).at_most(:once).and_return(false)
            @mock_fuse.should_receive(:can_mkdir?).with(@checkfile).at_most(:once).and_return(false)
            stat = @fuse.getattr(@mock_context,dir)
            #Apparently find relies on nlink accurately listing the number of files/directories or nlink being 1
            stat.nlink.should == 1
            filetype(stat.mode).should == FuseFS::Stat::S_IFDIR
            permissions(stat.mode).should == 0555
          end
          
          
          it "should return writable mode if can_mkdir?" do
          	  @mock_fuse.should_receive(:can_mkdir?).with(@checkfile).at_most(:once).and_return(true)
            
            stat = @fuse.getattr(@mock_context,dir)
            permissions(stat.mode).should == 0777
          end
          
          it "should return writable mode if can_write?" do
            @mock_fuse.should_receive(:can_write?).with(@checkfile).at_most(:once).and_return(true)
            
            stat = @fuse.getattr(@mock_context,dir)
            permissions(stat.mode).should == 0777
            
          end
          
          it "should return times in the result if available" do
          	  @mock_fuse.should_receive(:times).with(dir).and_return([10,20,30])
          	  stat = @fuse.getattr(@mock_context,dir)
          	  stat.atime.should == 10
          	  stat.mtime.should == 20
          	  stat.ctime.should == 30
          end
        end
      end
      
      describe "a file" do
      	  
      	before(:each) do
      		@file="/aPath/aFile"
            @mock_fuse.stub!(:directory?).and_return(false)
            @mock_fuse.should_receive(:file?).with(@file).at_most(:once).and_return(true)
        end
          
      	  
      	  it "should return a Stat like object representing a file" do
      	  	  stat = @fuse.getattr(@mock_context,@file)
             (stat.mode & FuseFS::Stat::S_IFDIR).should == 0
             (stat.mode & FuseFS::Stat::S_IFREG).should_not == 0
             permissions(stat.mode).should == 0444
      	  end
      	  
      	  it "should indicate executable mode if executable?" do
      	  	  @mock_fuse.should_receive(:executable?).with(@file).and_return(true)
      	  	  stat = @fuse.getattr(@mock_context,@file)
      	  	  permissions(stat.mode).should == 0555
      	  end
      	  
      	  it "should indicate writable mode if can_write?" do
      	  	  @mock_fuse.should_receive(:can_write?).with(@file).and_return(true)
      	  	  stat = @fuse.getattr(@mock_context,@file)
      	  	  permissions(stat.mode).should == 0666  
      	  end
      	  
      	  it "should by 777 mode if can_write? and exectuable?" do
      	  	  @mock_fuse.should_receive(:can_write?).with(@file).and_return(true)
      	  	  @mock_fuse.should_receive(:executable?).with(@file).and_return(true)
      	  	  stat = @fuse.getattr(@mock_context,@file)
      	  	  permissions(stat.mode).should == 0777 
      	  end
      	  
      	  it "should include size in the result if available" do
      	  	  @mock_fuse.should_receive(:size).with(@file).and_return(234)
      	  	  stat = @fuse.getattr(@mock_context,@file)
      	  	  stat.size.should == 234
       	  end
       	  
          it "should include times in the result if available" do
      	  	  @mock_fuse.should_receive(:times).with(@file).and_return([22,33,44])
      	  	  stat = @fuse.getattr(@mock_context,@file)
      	  	  stat.atime.should == 22
      	  	  stat.mtime.should == 33
      	  	  stat.ctime.should == 44
          end
      end
      
      it "should raise ENOENT for a path that does not exist" do
      	  @mock_fuse.should_receive(:file?).with(TEST_FILE).and_return(false)
      	  @mock_fuse.should_receive(:directory?).with(TEST_FILE).and_return(false)
      	  lambda{stat = @fuse.getattr(@mock_context,TEST_FILE) }.should raise_error(Errno::ENOENT)
      end
    end
 
    context "creating files and directories" do
    	
    	it ":mknod should raise EACCES unless :can_write?" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.should_receive(:can_write?).with(TEST_FILE).and_return(false)
    		lambda{@fuse.mknod(@mock_context,TEST_FILE,0100644,nil)}.should raise_error(Errno::EACCES)
    	end
    	
    	it ":mkdir should raise EACCES unless :can_mkdir?" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.should_receive(:can_mkdir?).with(TEST_FILE).and_return(false)
    		lambda{@fuse.mkdir(@mock_context,TEST_FILE,004555)}.should raise_error(Errno::EACCES)	
    	end
    	
    	it ":mknod should raise EACCES unless mode requests a regular file" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		lambda{@fuse.mknod(@mock_context,TEST_FILE,FuseFS::Stat::S_IFLNK | 0644,nil)}.should raise_error(Errno::EACCES)
    	end
    	
    	it ":mknod should result in getattr returning a Stat like object representing an empty file" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@fuse.mknod(@mock_context,TEST_FILE,FuseFS::Stat::S_IFREG | 0644,nil)
    		
    		stat = @fuse.getattr(@mock_context,TEST_FILE)
    		filetype(stat.mode).should == FuseFS::Stat::S_IFREG
    		stat.size.should == 0
    	end
    	
    	it ":mkdir should not raise error if can_mkdir?" do
    		@mock_fuse.should_receive(:can_mkdir?).with(TEST_FILE).and_return(true)
    		@fuse.mkdir(@mock_context,TEST_FILE,004555)	
    	end
      
    end
    
    context "reading files" do
    	it "should read the contents of a file" do
    		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_RDONLY
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:read_file).with(TEST_FILE).and_return("Hello World\n")
    		@fuse.open(@mock_context,TEST_FILE,ffi)
    		#to me fuse is backwards -- size, offset!
    		@fuse.read(@mock_context,TEST_FILE,5,0,ffi).should == "Hello"
    		@fuse.read(@mock_context,TEST_FILE,4,6,ffi).should == "Worl"
    		@fuse.read(@mock_context,TEST_FILE,10,8,ffi).should == "rld\n"
    		@fuse.flush(@mock_context,TEST_FILE,ffi)
    		@fuse.release(@mock_context,TEST_FILE,ffi)
    	end
    end
    
    context "writing files" do
    	it "should overwrite a file opened WR_ONLY" do
    		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_WRONLY
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:read_file).with(TEST_FILE).and_return("I'm writing a file\n")
    		@mock_fuse.should_receive(:write_to).once().with(TEST_FILE,"My new contents\n")
    		@fuse.open(@mock_context,TEST_FILE,ffi)
    		@fuse.ftruncate(@mock_context,TEST_FILE,0,ffi)
    		@fuse.write(@mock_context,TEST_FILE,"My new c",0,ffi)
    		@fuse.write(@mock_context,TEST_FILE,"ontents\n",8,ffi)
    		@fuse.flush(@mock_context,TEST_FILE,ffi)
    		#that's right flush can be called more than once.
    		@fuse.flush(@mock_context,TEST_FILE,ffi)
    		#but then we can write some more and flush again
    		@fuse.release(@mock_context,TEST_FILE,ffi)
    	end
    	
    	it "should append to a file opened WR_ONLY | APPEND" do
     		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_WRONLY | Fcntl::O_APPEND
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:read_file).with(TEST_FILE).and_return("I'm writing a file\n")
    		@mock_fuse.should_receive(:write_to).once().with(TEST_FILE,"I'm writing a file\nMy new contents\n")
    		@fuse.open(@mock_context,TEST_FILE,ffi)
    		@fuse.write(@mock_context,TEST_FILE,"My new c",0,ffi)
    		@fuse.write(@mock_context,TEST_FILE,"ontents\n",8,ffi)
    		@fuse.flush(@mock_context,TEST_FILE,ffi)
    		#that's right flush can be called more than once. But we should only write-to the first time
    		@fuse.flush(@mock_context,TEST_FILE,ffi)
    		@fuse.release(@mock_context,TEST_FILE,ffi)
   		
    	end
    	
    end
    context "raw reading"
    context "raw writing"

  end
  
  describe "a FuseFS filesystem with gid/uid specific behaviour" do
    it "should provide context uid and gid for all API methods"
  end
end


