require 'spec_helper'

describe FuseFS do
  
  TEST_FILE = "/aPath/aFile" 
  TEST_DIR = "/aPath"
  ROOT_PATH = "/"
  Struct.new("FuseFileInfo",:flags,:fh)
  
  describe "an empty FuseFS object" do
    before(:each) do
      @fuse = FuseFS::RFuseFS.new(Object.new())
    end
    
    it "should return an appropriate Stat for the root directory" do
      stat = @fuse.getattr(nil,ROOT_PATH)
      stat.should respond_to(:dev)
      (stat.mode & RFuse::Stat::S_IFDIR).should_not == 0
      (stat.mode & RFuse::Stat::S_IFREG).should == 0
      permissions(stat.mode).should == 0555
    end
    
    it "should have an empty root directory" do
      filler = mock("entries_filler")
      filler.should_receive(:push).with(".",nil,0)
      filler.should_receive(:push).with("..",nil,0)
      @fuse.readdir(nil,"/",filler,nil,nil)
    end
    
    it "should raise ENOENT for other paths" do
      lambda { @fuse.getattr(nil,"/somepath") }.should raise_error(Errno::ENOENT)
    end
    
    it "should not allow new files or directories" do
      lambda { @fuse.mknod(nil,"/afile",0100644,0,0) }.should raise_error(Errno::EACCES)
      lambda { @fuse.mkdir(nil,"/adir",0040555) }.should raise_error(Errno::EACCES)
    end
  end
  
  describe "a FuseFS filesystem" do
    before(:each) do
      @mock_fuse = FuseFS::FuseDir.new()
      @fuse = FuseFS::RFuseFS.new(@mock_fuse)
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
        @fuse.readdir(nil,"/apath",filler,nil,nil)
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
            stat = @fuse.getattr(nil,dir)
            #Apparently find relies on nlink accurately listing the number of files/directories or nlink being 1
            stat.nlink.should == 1
            filetype(stat.mode).should == RFuse::Stat::S_IFDIR
            permissions(stat.mode).should == 0555
          end
          
          
          it "should return writable mode if can_mkdir?" do
          	  @mock_fuse.should_receive(:can_mkdir?).with(@checkfile).at_most(:once).and_return(true)
            
            stat = @fuse.getattr(nil,dir)
            permissions(stat.mode).should == 0777
          end
          
          it "should return writable mode if can_write?" do
            @mock_fuse.should_receive(:can_write?).with(@checkfile).at_most(:once).and_return(true)
            
            stat = @fuse.getattr(nil,dir)
            permissions(stat.mode).should == 0777
            
          end
          
          it "should return times in the result if available" do
          	  @mock_fuse.should_receive(:times).with(dir).and_return([10,20,30])
          	  stat = @fuse.getattr(nil,dir)
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
      	  	  stat = @fuse.getattr(nil,@file)
             (stat.mode & RFuse::Stat::S_IFDIR).should == 0
             (stat.mode & RFuse::Stat::S_IFREG).should_not == 0
             permissions(stat.mode).should == 0444
      	  end
      	  
      	  it "should indicate executable mode if executable?" do
      	  	  @mock_fuse.should_receive(:executable?).with(@file).and_return(true)
      	  	  stat = @fuse.getattr(nil,@file)
      	  	  permissions(stat.mode).should == 0555
      	  end
      	  
      	  it "should indicate writable mode if can_write?" do
      	  	  @mock_fuse.should_receive(:can_write?).with(@file).and_return(true)
      	  	  stat = @fuse.getattr(nil,@file)
      	  	  permissions(stat.mode).should == 0666  
      	  end
      	  
      	  it "should by 777 mode if can_write? and exectuable?" do
      	  	  @mock_fuse.should_receive(:can_write?).with(@file).and_return(true)
      	  	  @mock_fuse.should_receive(:executable?).with(@file).and_return(true)
      	  	  stat = @fuse.getattr(nil,@file)
      	  	  permissions(stat.mode).should == 0777 
      	  end
      	  
      	  it "should include size in the result if available" do
      	  	  @mock_fuse.should_receive(:size).with(@file).and_return(234)
      	  	  stat = @fuse.getattr(nil,@file)
      	  	  stat.size.should == 234
       	  end
       	  
          it "should include times in the result if available" do
      	  	  @mock_fuse.should_receive(:times).with(@file).and_return([22,33,44])
      	  	  stat = @fuse.getattr(nil,@file)
      	  	  stat.atime.should == 22
      	  	  stat.mtime.should == 33
      	  	  stat.ctime.should == 44
          end
      end
      
      it "should raise ENOENT for a path that does not exist" do
      	  @mock_fuse.should_receive(:file?).with(TEST_FILE).and_return(false)
      	  @mock_fuse.should_receive(:directory?).with(TEST_FILE).and_return(false)
      	  lambda{stat = @fuse.getattr(nil,TEST_FILE) }.should raise_error(Errno::ENOENT)
      end
    end
 
    context "creating files and directories" do
    	
    	it ":mknod should raise EACCES unless :can_write?" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.should_receive(:can_write?).with(TEST_FILE).and_return(false)
    		lambda{@fuse.mknod(nil,TEST_FILE,0100644,0,0)}.should raise_error(Errno::EACCES)
    	end
    	
    	it ":mkdir should raise EACCES unless :can_mkdir?" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.should_receive(:can_mkdir?).with(TEST_FILE).and_return(false)
    		lambda{@fuse.mkdir(nil,TEST_FILE,004555)}.should raise_error(Errno::EACCES)	
    	end
    	
    	it ":mknod should raise EACCES unless mode requests a regular file" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		lambda{@fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFLNK | 0644,0,0)}.should raise_error(Errno::EACCES)
    	end
    	
    	it ":mknod should result in getattr returning a Stat like object representing an empty file" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)
    		
    		stat = @fuse.getattr(nil,TEST_FILE)
    		filetype(stat.mode).should == RFuse::Stat::S_IFREG
    		stat.size.should == 0
    	end
        
        it "should create zero length files" do
     		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_WRONLY
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
            @mock_fuse.should_receive(:write_to).once.with(TEST_FILE,"")
    		@fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)
    		@fuse.open(nil,TEST_FILE,ffi)
    		@fuse.flush(nil,TEST_FILE,ffi)
    		@fuse.release(nil,TEST_FILE,ffi)
        end

    	it ":mkdir should not raise error if can_mkdir?" do
    		@mock_fuse.should_receive(:can_mkdir?).with(TEST_FILE).and_return(true)
    		@fuse.mkdir(nil,TEST_FILE,004555)
    	end
      
    end
    
    context "reading files" do
    	it "should read the contents of a file" do
    		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_RDONLY
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:read_file).with(TEST_FILE).and_return("Hello World\n")
    		@fuse.open(nil,TEST_FILE,ffi)
    		#to me fuse is backwards -- size, offset!
    		@fuse.read(nil,TEST_FILE,5,0,ffi).should == "Hello"
    		@fuse.read(nil,TEST_FILE,4,6,ffi).should == "Worl"
    		@fuse.read(nil,TEST_FILE,10,8,ffi).should == "rld\n"
    		@fuse.flush(nil,TEST_FILE,ffi)
    		@fuse.release(nil,TEST_FILE,ffi)
    	end
    end
    
    context "writing files" do
    	it "should overwrite a file opened WR_ONLY" do
    		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_WRONLY
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:read_file).with(TEST_FILE).and_return("I'm writing a file\n")
    		@mock_fuse.should_receive(:write_to).once().with(TEST_FILE,"My new contents\n")
    		@fuse.open(nil,TEST_FILE,ffi)
    		@fuse.ftruncate(nil,TEST_FILE,0,ffi)
    		@fuse.write(nil,TEST_FILE,"My new c",0,ffi)
    		@fuse.write(nil,TEST_FILE,"ontents\n",8,ffi)
    		@fuse.flush(nil,TEST_FILE,ffi)
    		#that's right flush can be called more than once.
    		@fuse.flush(nil,TEST_FILE,ffi)
    		#but then we can write some more and flush again
    		@fuse.release(nil,TEST_FILE,ffi)
    	end
    	
    	it "should append to a file opened WR_ONLY | APPEND" do
     		ffi = Struct::FuseFileInfo.new()
    		ffi.flags = Fcntl::O_WRONLY | Fcntl::O_APPEND
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:read_file).with(TEST_FILE).and_return("I'm writing a file\n")
    		@mock_fuse.should_receive(:write_to).once().with(TEST_FILE,"I'm writing a file\nMy new contents\n")
    		@fuse.open(nil,TEST_FILE,ffi)
    		@fuse.write(nil,TEST_FILE,"My new c",0,ffi)
    		@fuse.write(nil,TEST_FILE,"ontents\n",8,ffi)
    		@fuse.flush(nil,TEST_FILE,ffi)
    		#that's right flush can be called more than once. But we should only write-to the first time
    		@fuse.flush(nil,TEST_FILE,ffi)
    		@fuse.release(nil,TEST_FILE,ffi)
   		
    	end

    	it "should do sensible things for files opened RDWR"
    
        it "should pass on buffered data when requested (fsync)"

    end
    
    context "raw reading" do
    	it "should call the raw_read/raw_close if raw_open returns true" do
			ffi = Struct::FuseFileInfo.new()
			ffi.flags = Fcntl::O_RDONLY 
			@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
			@mock_fuse.should_receive(:raw_open).with(TEST_FILE,"r",true).and_return("raw")
			@mock_fuse.should_receive(:raw_read).with(TEST_FILE,5,0,"raw").and_return("12345")
			@mock_fuse.should_receive(:raw_read).with(TEST_FILE,5,5,"raw").and_return("67890")
			@mock_fuse.should_receive(:raw_close).with(TEST_FILE,"raw")
			@fuse.open(nil,TEST_FILE,ffi)
			@fuse.read(nil,TEST_FILE,0,5,ffi).should == "12345"
			@fuse.read(nil,TEST_FILE,5,5,ffi).should == "67890"
			@fuse.flush(nil,TEST_FILE,ffi)
			@fuse.release(nil,TEST_FILE,ffi)
    	end
    	
    end
    
    context "raw writing" do
		it "should call other raw_* methods if raw_open returns true" do
			ffi = Struct::FuseFileInfo.new()
			ffi.flags = Fcntl::O_WRONLY
			raw = Object.new()
			@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
			@mock_fuse.should_receive(:raw_open).with(TEST_FILE,"w",true).and_return(raw)
			@mock_fuse.should_receive(:raw_truncate).with(TEST_FILE,0,raw)
			@mock_fuse.should_receive(:raw_write).with(TEST_FILE,0,5,"12345",raw).once().and_return(5)
			@mock_fuse.should_receive(:raw_write).with(TEST_FILE,5,5,"67890",raw).once().and_return(5)
            @mock_fuse.should_receive(:raw_sync).with(TEST_FILE, false, raw)
			@mock_fuse.should_receive(:raw_close).with(TEST_FILE,raw)
			@fuse.open(nil,TEST_FILE,ffi)
			@fuse.ftruncate(nil,TEST_FILE,0,ffi)
    		@fuse.write(nil,TEST_FILE,"12345",0,ffi).should == 5
            @fuse.fsync(nil,TEST_FILE,0,ffi)
			@fuse.write(nil,TEST_FILE,"67890",5,ffi).should == 5
			@fuse.flush(nil,TEST_FILE,ffi)
			@fuse.release(nil,TEST_FILE,ffi)
		end

		it "should pass 'wa' to raw_open if fuse sends WRONLY | APPEND" do
            ffi = Struct::FuseFileInfo.new()
			ffi.flags = Fcntl::O_WRONLY | Fcntl::O_APPEND
			raw = Object.new()
			@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
			@mock_fuse.should_receive(:raw_open).with(TEST_FILE,"wa",true).and_return(raw)
			@fuse.open(nil,TEST_FILE,ffi)			
		end
	end
	
	context "deleting files" do
	    it "should raise EACCES unless :can_delete?" do
	        @mock_fuse.should_receive(:can_delete?).with(TEST_FILE).and_return(false)
	        lambda {@fuse.unlink(nil,TEST_FILE)}.should raise_error(Errno::EACCES)
	    end
	    
	    it "should :delete without error if :can_delete?" do
	       @mock_fuse.stub!(:can_delete?).with(TEST_FILE).and_return(true)
           @mock_fuse.should_receive(:delete).with(TEST_FILE)
	       @fuse.unlink(nil,TEST_FILE)
	    end

        it "should remove entries created with mknod that have never been opened" do
    		@mock_fuse.stub!(:file?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:directory?).with(TEST_FILE).and_return(false)
    		@mock_fuse.stub!(:can_delete?).with(TEST_FILE).and_return(true)
    		@mock_fuse.stub!(:can_write?).with(TEST_FILE).and_return(true)
    		@fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)

            @fuse.unlink(nil,TEST_FILE)
            lambda {@fuse.getattr(nil,TEST_FILE)}.should raise_error(Errno::ENOENT)
        end
	end
	
	context "deleting directories" do
	    it "should raise EACCES unless :can_rmdir?" do
	       @mock_fuse.should_receive(:can_rmdir?).with(TEST_DIR).and_return(false)
	       lambda{@fuse.rmdir(nil,TEST_DIR)}.should raise_error(Errno::EACCES)
	    end
	    
	    it "should :rmdir without error if :can_rmdir?" do
	        @mock_fuse.stub!(:can_rmdir?).with(TEST_DIR).and_return(true)
	        @fuse.rmdir(nil,TEST_DIR)
	    end
	end
	
	context "touching files" do
        it "should call :touch in response to utime" do
            @mock_fuse.should_receive(:touch).with(TEST_FILE,220)
            @fuse.utime(nil,TEST_FILE,100,220)
        end  
    end
    
    context "renaming files" do
        before(:each) do
          @oldfile = "/aPath/oldFile"
          @newfile = "/aNewFile"
          @mock_fuse.stub!(:file?).with(@oldfile).and_return(true)
          @mock_fuse.stub!(:directory?).with(@oldfile).and_return(false)
        end
        it "should raise EACCES unless :can_write? the new file" do
            @mock_fuse.stub!(:can_delete?).with(@oldfile).and_return(true)
            @mock_fuse.should_receive(:can_write?).with(@newfile).and_return(false)
            lambda {@fuse.rename(nil,@oldfile,@newfile)}.should raise_error(Errno::EACCES)
        end

        it "should raise EACCES unless :can_delete the old file" do
            @mock_fuse.stub!(:can_write?).with(@newfile).and_return(true)
            @mock_fuse.should_receive(:can_delete?).with(@oldfile).and_return(false)
            lambda {@fuse.rename(nil,@oldfile,@newfile)}.should raise_error(Errno::EACCES)
        end

        it "should copy and delete files" do
            @mock_fuse.stub!(:can_write?).with(@newfile).and_return(true)
            @mock_fuse.stub!(:can_delete?).with(@oldfile).and_return(true) 
            @mock_fuse.should_receive(:read_file).with(@oldfile).and_return("some contents\n")
            @mock_fuse.should_receive(:write_to).with(@newfile,"some contents\n")
            @mock_fuse.should_receive(:delete).with(@oldfile)
            @fuse.rename(nil,@oldfile,@newfile)
        end

        it "should not copy and delete files if fs responds_to? :rename" do
            @mock_fuse.should_receive(:rename).with(@oldfile,@newfile).and_return(true)
            @fuse.rename(nil,@oldfile,@newfile)
        end

        it "should raise EACCES if moving a directory and rename not supported" do
            @mock_fuse.stub!(:file?).with(@oldfile).and_return(false)
            @mock_fuse.stub!(:directory?).with(@oldfile).and_return(true)
            @mock_fuse.stub!(:can_write?).with(@newfile).and_return(true)
            @mock_fuse.stub!(:can_delete?).with(@oldfile).and_return(true) 
            lambda{@fuse.rename(nil,@oldfile,@newfile)}.should raise_error(Errno::EACCES)
        end

    end
    context "extended attributes" do

        let(:xattr) { mock(:xattr) }
        before(:each) { @mock_fuse.stub!(:xattr).with(TEST_FILE).and_return(xattr) }

        it "should list attributes via #keys on result of #xattr" do
            xattr.should_receive(:keys).and_return(["one","two"])
            @fuse.listxattr(nil,TEST_FILE).should == [ "one","two" ]
        end

        it "should get attributes via #xattr.[]" do
            xattr.should_receive(:[]).with("user.one").and_return("one")

            @fuse.getxattr(nil,TEST_FILE,"user.one").should == "one"
        end

        it "should set attributes via #xattr.[]=" do
            xattr.should_receive(:[]=).with("user.two","two")

            @fuse.setxattr(nil,TEST_FILE,"user.two","two",0)
        end

        it "should remove attributes via #xattr.delete" do
            xattr.should_receive(:delete).with("user.three")

            @fuse.removexattr(nil,TEST_FILE,"user.three")
        end

        it "should raise ENODATA when #xattr.[] returns nil" do

            xattr.should_receive(:[]).with("user.xxxx").and_return(nil)
            lambda{@fuse.getxattr(nil,TEST_FILE,"user.xxxx") }.should raise_error(Errno::ENODATA)
        end
    end

    context "#statfs" do
        # used space, used files, total_space, total_files
        let(:stats) { [ 1000 * 1024, 5, 1200 * 1024, 12 ] }
        it "should convert simple array into StatVfs" do
    
            @mock_fuse.should_receive(:statistics).with(TEST_FILE).and_return(stats)

            result = @fuse.statfs(nil,TEST_FILE)
            result.should be_kind_of(RFuse::StatVfs)
            result.f_bsize.should == 1024
            result.f_blocks.should == 1200
            result.f_bavail.should == 200
            result.f_files.should == 12
            result.f_ffree.should == 7
        end

        it "passes on raw statistics" do
            statvfs = Object.new()
            @mock_fuse.should_receive(:statistics).with(TEST_FILE).and_return(statvfs)

            @fuse.statfs(nil,TEST_FILE).should equal(statvfs)
        end

    end
  end
  
  describe "a FuseFS filesystem with gid/uid specific behaviour" do
    it "should provide context uid and gid for all API methods"
  end
end


