require 'spec_helper'

describe FuseFS do

  TEST_FILE = "/aPath/aFile"
  TEST_DIR = "/aPath"
  ROOT_PATH = "/"
  Struct.new("FuseFileInfo",:flags,:fh)

  describe "an empty Root object" do
    before(:each) do
      @fuse = FuseFS::Fuse::Root.new(Object.new())
    end

    it "should return an appropriate Stat for the root directory" do
      stat = @fuse.getattr(nil,ROOT_PATH)
      expect(stat).to respond_to(:dev)
      expect(stat.mode & RFuse::Stat::S_IFDIR).not_to eq(0)
      expect(stat.mode & RFuse::Stat::S_IFREG).to eq(0)
      expect(permissions(stat.mode)).to eq(0555)
    end

    it "should have an empty root directory" do
      filler = double("entries_filler")
      expect(filler).to receive(:push).with(".",nil,0)
      expect(filler).to receive(:push).with("..",nil,0)
      @fuse.readdir(nil,"/",filler,nil,nil)
    end

    it "should raise ENOENT for other paths" do
      expect { @fuse.getattr(nil,"/somepath") }.to raise_error(Errno::ENOENT)
    end

    it "should not allow new files or directories" do
      expect { @fuse.mknod(nil,"/afile",0100644,0,0) }.to raise_error(Errno::EACCES)
      expect { @fuse.mkdir(nil,"/adir",0040555) }.to raise_error(Errno::EACCES)
    end
  end

  describe "a FuseFS filesystem" do
    before(:each) do
      @mock_fuse = FuseFS::FuseDir.new()
      @fuse = FuseFS::Fuse::Root.new(@mock_fuse)
    end

    context("handling signals") do
      it "should pass on signals" do
        expect(@mock_fuse).to receive(:sighup) { }
        fuse = FuseFS::Fuse::Root.new(@mock_fuse)
        fuse.sighup
      end
    end

    describe :readdir do
      before(:each) do
        expect(@mock_fuse).to receive(:contents).with("/apath").and_return(["afile"])
      end

      it "should add  . and .. to the results of :contents when listing a directory" do
        filler = double("entries_filler")
        expect(filler).to receive(:push).with(".",nil,0)
        expect(filler).to receive(:push).with("..",nil,0)
        expect(filler).to receive(:push).with("afile",nil,0)
        @fuse.readdir(nil,"/apath",filler,nil,nil)
      end

    end

    describe :getattr do

      #Root directory is special (ish) so we need to run these specs twice.
      [ROOT_PATH,TEST_DIR].each do |dir|

        context "of a directory #{ dir }" do

          before(:each) do
            allow(@mock_fuse).to receive(:file?).and_return(false)
            expect(@mock_fuse).to receive(:directory?).with(dir).at_most(:once).and_return(true)
            @checkfile =  (dir == "/" ? "" : dir ) + FuseFS::Fuse::Root::CHECK_FILE
          end

          it "should return a Stat like object representing a directory" do
            expect(@mock_fuse).to receive(:can_write?).with(@checkfile).at_most(:once).and_return(false)
            expect(@mock_fuse).to receive(:can_mkdir?).with(@checkfile).at_most(:once).and_return(false)
            stat = @fuse.getattr(nil,dir)
            #Apparently find relies on nlink accurately listing the number of files/directories or nlink being 1
            expect(stat.nlink).to eq(1)
            expect(filetype(stat.mode)).to eq(RFuse::Stat::S_IFDIR)
            expect(permissions(stat.mode)).to eq(0555)
          end


          it "should return writable mode if can_mkdir?" do
            expect(@mock_fuse).to receive(:can_mkdir?).with(@checkfile).at_most(:once).and_return(true)

            stat = @fuse.getattr(nil,dir)
            expect(permissions(stat.mode)).to eq(0777)
          end

          it "should return writable mode if can_write?" do
            expect(@mock_fuse).to receive(:can_write?).with(@checkfile).at_most(:once).and_return(true)

            stat = @fuse.getattr(nil,dir)
            expect(permissions(stat.mode)).to eq(0777)

          end

          it "should return times in the result if available" do
            expect(@mock_fuse).to receive(:times).with(dir).and_return([10,20,30])
            stat = @fuse.getattr(nil,dir)
            expect(stat.atime).to eq(10)
            expect(stat.mtime).to eq(20)
            expect(stat.ctime).to eq(30)
          end
        end
      end

      describe "a file" do

        before(:each) do
          @file="/aPath/aFile"
          allow(@mock_fuse).to receive(:directory?).and_return(false)
          expect(@mock_fuse).to receive(:file?).with(@file).at_most(:once).and_return(true)
        end


        it "should return a Stat like object representing a file" do
          stat = @fuse.getattr(nil,@file)
          expect(stat.mode & RFuse::Stat::S_IFDIR).to eq(0)
          expect(stat.mode & RFuse::Stat::S_IFREG).not_to eq(0)
          expect(permissions(stat.mode)).to eq(0444)
        end

        it "should indicate executable mode if executable?" do
          expect(@mock_fuse).to receive(:executable?).with(@file).and_return(true)
          stat = @fuse.getattr(nil,@file)
          expect(permissions(stat.mode)).to eq(0555)
        end

        it "should indicate writable mode if can_write?" do
          expect(@mock_fuse).to receive(:can_write?).with(@file).and_return(true)
          stat = @fuse.getattr(nil,@file)
          expect(permissions(stat.mode)).to eq(0666)
        end

        it "should by 777 mode if can_write? and exectuable?" do
          expect(@mock_fuse).to receive(:can_write?).with(@file).and_return(true)
          expect(@mock_fuse).to receive(:executable?).with(@file).and_return(true)
          stat = @fuse.getattr(nil,@file)
          expect(permissions(stat.mode)).to eq(0777)
        end

        it "should include size in the result if available" do
          expect(@mock_fuse).to receive(:size).with(@file).and_return(234)
          stat = @fuse.getattr(nil,@file)
          expect(stat.size).to eq(234)
        end

        it "should include times in the result if available" do
          expect(@mock_fuse).to receive(:times).with(@file).and_return([22,33,44])
          stat = @fuse.getattr(nil,@file)
          expect(stat.atime).to eq(22)
          expect(stat.mtime).to eq(33)
          expect(stat.ctime).to eq(44)
        end
      end

      it "should raise ENOENT for a path that does not exist" do
        expect(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        expect(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        expect{stat = @fuse.getattr(nil,TEST_FILE) }.to raise_error(Errno::ENOENT)
      end
    end

    context "creating files and directories" do

      it ":mknod should raise EACCES unless :can_write?" do
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        expect(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(false)
        expect{@fuse.mknod(nil,TEST_FILE,0100644,0,0)}.to raise_error(Errno::EACCES)
      end

      it ":mkdir should raise EACCES unless :can_mkdir?" do
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        expect(@mock_fuse).to receive(:can_mkdir?).with(TEST_FILE).and_return(false)
        expect{@fuse.mkdir(nil,TEST_FILE,004555)}.to raise_error(Errno::EACCES)
      end

      it ":mknod should raise EACCES unless mode requests a regular file" do
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        expect{@fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFLNK | 0644,0,0)}.to raise_error(Errno::EACCES)
      end

      it ":mknod should result in getattr returning a Stat like object representing an empty file" do
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        @fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)

        stat = @fuse.getattr(nil,TEST_FILE)
        expect(filetype(stat.mode)).to eq(RFuse::Stat::S_IFREG)
        expect(stat.size).to eq(0)
      end

      it "should create zero length files" do
        ffi = Struct::FuseFileInfo.new()
        ffi.flags = Fcntl::O_WRONLY
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        expect(@mock_fuse).to receive(:write_to).once.with(TEST_FILE,"")
        @fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)
        @fuse.open(nil,TEST_FILE,ffi)
        @fuse.flush(nil,TEST_FILE,ffi)
        @fuse.release(nil,TEST_FILE,ffi)
      end

      it ":mkdir should not raise error if can_mkdir?" do
        expect(@mock_fuse).to receive(:can_mkdir?).with(TEST_FILE).and_return(true)
        @fuse.mkdir(nil,TEST_FILE,004555)
      end

    end

    context "reading files" do
      it "should read the contents of a file" do
        ffi = Struct::FuseFileInfo.new()
        ffi.flags = Fcntl::O_RDONLY
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(true)
        allow(@mock_fuse).to receive(:read_file).with(TEST_FILE).and_return("Hello World\n")
        @fuse.open(nil,TEST_FILE,ffi)
        #to me fuse is backwards -- size, offset!
        expect(@fuse.read(nil,TEST_FILE,5,0,ffi)).to eq("Hello")
        expect(@fuse.read(nil,TEST_FILE,4,6,ffi)).to eq("Worl")
        expect(@fuse.read(nil,TEST_FILE,10,8,ffi)).to eq("rld\n")
        @fuse.flush(nil,TEST_FILE,ffi)
        @fuse.release(nil,TEST_FILE,ffi)
      end
    end

    context "writing files" do
      it "should overwrite a file opened WR_ONLY" do
        ffi = Struct::FuseFileInfo.new()
        ffi.flags = Fcntl::O_WRONLY
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        allow(@mock_fuse).to receive(:read_file).with(TEST_FILE).and_return("I'm writing a file\n")
        expect(@mock_fuse).to receive(:write_to).once().with(TEST_FILE,"My new contents\n")
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
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        allow(@mock_fuse).to receive(:read_file).with(TEST_FILE).and_return("I'm writing a file\n")
        expect(@mock_fuse).to receive(:write_to).once().with(TEST_FILE,"I'm writing a file\nMy new contents\n")
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
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        expect(@mock_fuse).to receive(:raw_open).with(TEST_FILE,"r",true).and_return("raw")
        expect(@mock_fuse).to receive(:raw_read).with(TEST_FILE,5,0,"raw").and_return("12345")
        expect(@mock_fuse).to receive(:raw_read).with(TEST_FILE,5,5,"raw").and_return("67890")
        expect(@mock_fuse).to receive(:raw_close).with(TEST_FILE,"raw")
        @fuse.open(nil,TEST_FILE,ffi)
        expect(@fuse.read(nil,TEST_FILE,0,5,ffi)).to eq("12345")
        expect(@fuse.read(nil,TEST_FILE,5,5,ffi)).to eq("67890")
        @fuse.flush(nil,TEST_FILE,ffi)
        @fuse.release(nil,TEST_FILE,ffi)
      end

    end

    context "raw writing" do
      it "should call other raw_* methods if raw_open returns true" do
        ffi = Struct::FuseFileInfo.new()
        ffi.flags = Fcntl::O_WRONLY
        raw = Object.new()
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        expect(@mock_fuse).to receive(:raw_open).with(TEST_FILE,"w",true).and_return(raw)
        expect(@mock_fuse).to receive(:raw_truncate).with(TEST_FILE,0,raw)
        expect(@mock_fuse).to receive(:raw_write).with(TEST_FILE,0,5,"12345",raw).once().and_return(5)
        expect(@mock_fuse).to receive(:raw_write).with(TEST_FILE,5,5,"67890",raw).once().and_return(5)
        expect(@mock_fuse).to receive(:raw_sync).with(TEST_FILE, false, raw)
        expect(@mock_fuse).to receive(:raw_close).with(TEST_FILE,raw)
        @fuse.open(nil,TEST_FILE,ffi)
        @fuse.ftruncate(nil,TEST_FILE,0,ffi)
        expect(@fuse.write(nil,TEST_FILE,"12345",0,ffi)).to eq(5)
        @fuse.fsync(nil,TEST_FILE,0,ffi)
        expect(@fuse.write(nil,TEST_FILE,"67890",5,ffi)).to eq(5)
        @fuse.flush(nil,TEST_FILE,ffi)
        @fuse.release(nil,TEST_FILE,ffi)
      end

      it "should clean up created files" do
        ffi = Struct::FuseFileInfo.new()
        ffi.flags = Fcntl::O_WRONLY
        raw = Object.new()
        allow(@mock_fuse).to receive(:directory?).and_return(false)
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false,true)
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        expect(@mock_fuse).to receive(:raw_open).with(TEST_FILE,"w",true).and_return(raw)
        expect(@mock_fuse).to receive(:raw_close).with(TEST_FILE,raw)
        expect(@mock_fuse).to receive(:size).with(TEST_FILE).and_return(25)

        expect { @fuse.getattr(nil,TEST_FILE) }.to raise_error(Errno::ENOENT)
        @fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)
        @fuse.open(nil,TEST_FILE,ffi)
        @fuse.flush(nil,TEST_FILE,ffi)
        @fuse.release(nil,TEST_FILE,ffi)
        stat = @fuse.getattr(nil,TEST_FILE)
        stat.size = 25
      end

      it "should pass 'wa' to raw_open if fuse sends WRONLY | APPEND" do
        ffi = Struct::FuseFileInfo.new()
        ffi.flags = Fcntl::O_WRONLY | Fcntl::O_APPEND
        raw = Object.new()
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        expect(@mock_fuse).to receive(:raw_open).with(TEST_FILE,"wa",true).and_return(raw)
        @fuse.open(nil,TEST_FILE,ffi)
      end
    end

    context "deleting files" do
      it "should raise EACCES unless :can_delete?" do
        expect(@mock_fuse).to receive(:can_delete?).with(TEST_FILE).and_return(false)
        expect {@fuse.unlink(nil,TEST_FILE)}.to raise_error(Errno::EACCES)
      end

      it "should :delete without error if :can_delete?" do
        allow(@mock_fuse).to receive(:can_delete?).with(TEST_FILE).and_return(true)
        expect(@mock_fuse).to receive(:delete).with(TEST_FILE)
        @fuse.unlink(nil,TEST_FILE)
      end

      it "should remove entries created with mknod that have never been opened" do
        allow(@mock_fuse).to receive(:file?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(TEST_FILE).and_return(false)
        allow(@mock_fuse).to receive(:can_delete?).with(TEST_FILE).and_return(true)
        allow(@mock_fuse).to receive(:can_write?).with(TEST_FILE).and_return(true)
        @fuse.mknod(nil,TEST_FILE,RFuse::Stat::S_IFREG | 0644,0,0)

        @fuse.unlink(nil,TEST_FILE)
        expect {@fuse.getattr(nil,TEST_FILE)}.to raise_error(Errno::ENOENT)
      end
    end

    context "deleting directories" do
      it "should raise EACCES unless :can_rmdir?" do
        expect(@mock_fuse).to receive(:can_rmdir?).with(TEST_DIR).and_return(false)
        expect{@fuse.rmdir(nil,TEST_DIR)}.to raise_error(Errno::EACCES)
      end

      it "should :rmdir without error if :can_rmdir?" do
        allow(@mock_fuse).to receive(:can_rmdir?).with(TEST_DIR).and_return(true)
        @fuse.rmdir(nil,TEST_DIR)
      end
    end

    context "touching files" do
      it "should call :touch in response to utime" do
        expect(@mock_fuse).to receive(:touch).with(TEST_FILE,220)
        @fuse.utime(nil,TEST_FILE,100,220)
      end
    end

    context "renaming files" do
      before(:each) do
        @oldfile = "/aPath/oldFile"
        @newfile = "/aNewFile"
        allow(@mock_fuse).to receive(:file?).with(@oldfile).and_return(true)
        allow(@mock_fuse).to receive(:directory?).with(@oldfile).and_return(false)
      end
      it "should raise EACCES unless :can_write? the new file" do
        allow(@mock_fuse).to receive(:can_delete?).with(@oldfile).and_return(true)
        expect(@mock_fuse).to receive(:can_write?).with(@newfile).and_return(false)
        expect {@fuse.rename(nil,@oldfile,@newfile)}.to raise_error(Errno::EACCES)
      end

      it "should raise EACCES unless :can_delete the old file" do
        allow(@mock_fuse).to receive(:can_write?).with(@newfile).and_return(true)
        expect(@mock_fuse).to receive(:can_delete?).with(@oldfile).and_return(false)
        expect {@fuse.rename(nil,@oldfile,@newfile)}.to raise_error(Errno::EACCES)
      end

      it "should copy and delete files" do
        allow(@mock_fuse).to receive(:can_write?).with(@newfile).and_return(true)
        allow(@mock_fuse).to receive(:can_delete?).with(@oldfile).and_return(true)
        expect(@mock_fuse).to receive(:read_file).with(@oldfile).and_return("some contents\n")
        expect(@mock_fuse).to receive(:write_to).with(@newfile,"some contents\n")
        expect(@mock_fuse).to receive(:delete).with(@oldfile)
        @fuse.rename(nil,@oldfile,@newfile)
      end

      it "should not copy and delete files if fs responds_to? :rename" do
        expect(@mock_fuse).to receive(:rename).with(@oldfile,@newfile).and_return(true)
        @fuse.rename(nil,@oldfile,@newfile)
      end

      it "should raise EACCES if moving a directory and rename not supported" do
        allow(@mock_fuse).to receive(:file?).with(@oldfile).and_return(false)
        allow(@mock_fuse).to receive(:directory?).with(@oldfile).and_return(true)
        allow(@mock_fuse).to receive(:can_write?).with(@newfile).and_return(true)
        allow(@mock_fuse).to receive(:can_delete?).with(@oldfile).and_return(true)
        expect{@fuse.rename(nil,@oldfile,@newfile)}.to raise_error(Errno::EACCES)
      end

    end
    context "extended attributes" do

      let(:xattr) { double(:xattr) }
      before(:each) { allow(@mock_fuse).to receive(:xattr).with(TEST_FILE).and_return(xattr) }

      it "should list attributes via #keys on result of #xattr" do
        expect(xattr).to receive(:keys).and_return(["one","two"])
        expect(@fuse.listxattr(nil,TEST_FILE)).to eq([ "one","two" ])
      end

      it "should get attributes via #xattr.[]" do
        expect(xattr).to receive(:[]).with("user.one").and_return("one")

        expect(@fuse.getxattr(nil,TEST_FILE,"user.one")).to eq("one")
      end

      it "should set attributes via #xattr.[]=" do
        expect(xattr).to receive(:[]=).with("user.two","two")

        @fuse.setxattr(nil,TEST_FILE,"user.two","two",0)
      end

      it "should remove attributes via #xattr.delete" do
        expect(xattr).to receive(:delete).with("user.three")

        @fuse.removexattr(nil,TEST_FILE,"user.three")
      end

      it "should raise ENODATA when #xattr.[] returns nil" do

        expect(xattr).to receive(:[]).with("user.xxxx").and_return(nil)
        expect{@fuse.getxattr(nil,TEST_FILE,"user.xxxx") }.to raise_error(Errno::ENODATA)
      end
    end

    context "#statfs" do
      # used space, used files, total_space, total_files
      let(:stats) { [ 1000 * 1024, 5, 1200 * 1024, 12 ] }
      it "should convert simple array into StatVfs" do

        expect(@mock_fuse).to receive(:statistics).with(TEST_FILE).and_return(stats)

        result = @fuse.statfs(nil,TEST_FILE)
        expect(result).to be_kind_of(RFuse::StatVfs)
        expect(result.f_bsize).to eq(1024)
        expect(result.f_blocks).to eq(1200)
        expect(result.f_bavail).to eq(200)
        expect(result.f_files).to eq(12)
        expect(result.f_ffree).to eq(7)
      end

      it "passes on raw statistics" do
        statvfs = Object.new()
        expect(@mock_fuse).to receive(:statistics).with(TEST_FILE).and_return(statvfs)

        expect(@fuse.statfs(nil,TEST_FILE)).to equal(statvfs)
      end

    end
  end

  describe "a FuseFS filesystem with gid/uid specific behaviour" do
    it "should provide context uid and gid for all API methods"
  end

end
