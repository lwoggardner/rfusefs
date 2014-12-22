require 'spec_helper'
require 'tmpdir'
require 'sys/filesystem'
require 'ffi-xattr'

describe FuseFS::MetaDir do

  context 'in ruby' do

    before(:each) do
      @metadir = FuseFS::MetaDir.new()
      @metadir.mkdir('/test')
      @metadir.mkdir('/test/hello')
      @metadir.mkdir('/test/hello/emptydir')
      @metadir.write_to('/test/hello/hello.txt', "Hello World!\n")
    end

    context 'general directory methods' do
      it 'should list directory contents' do
        expect(@metadir.contents('/')).to match_array(['test'])
        expect(@metadir.contents('/test')).to match_array(['hello'])
        expect(@metadir.contents('/test/hello')).to match_array(['hello.txt', 'emptydir'])
      end

      it 'should indicate paths which are/are not directories' do
        expect(@metadir.directory?('/test')).to be_truthy
        expect(@metadir.directory?('/test/hello')).to be_truthy
        expect(@metadir.directory?('/test/hello/hello.txt')).to be_falsey
        expect(@metadir.directory?('/nodir')).to be_falsey
        expect(@metadir.directory?('/test/nodir')).to be_falsey
      end

      it 'should indicate paths which are/are not files' do
        expect(@metadir.file?('/test')).to be_falsey
        expect(@metadir.file?('/test/nodir')).to be_falsey
        expect(@metadir.file?('/test/hello')).to be_falsey
        expect(@metadir.file?('/test/hello/hello.txt')).to be_truthy
      end

      it 'should indicate the size of a file' do
        expect(@metadir.size('/test/hello/hello.txt')).to be "Hello World!\n".length
      end

      it 'should report filesystem statistics' do
        expect(@metadir.statistics('/')).to eq([13, 5, nil, nil])
      end
    end

    context 'with write access' do

      around(:each) do |example|
        FuseFS::Fuse::Root.context(fuse_context(), &example)
      end

      before(:each) do
        expect(FuseFS::reader_uid).to eq(Process.uid)
        expect(FuseFS::reader_gid).to eq(Process.gid)
      end


      it 'should allow directory creation' do
        expect(@metadir.can_mkdir?('/test/otherdir')).to be_truthy
      end

      it 'should allow file creation and update' do
        expect(@metadir.can_write?('/test/hello/newfile')).to be_truthy
        expect(@metadir.can_write?('/test/hello/hello.txt')).to be_truthy
      end

      it 'should read files' do
        expect(@metadir.read_file('/test/hello/hello.txt')).to eq("Hello World!\n")
      end

      it 'should update existing files' do
        @metadir.write_to('/test/hello/hello.txt', 'new contents')
        expect(@metadir.read_file('/test/hello/hello.txt')).to eq('new contents')
      end

      it 'should not allow deletion of non empty directories' do
        expect(@metadir.can_rmdir?('/test/hello')).to be_falsey
      end

      it 'should delete directories' do
        @metadir.rmdir('/test/hello/emptydir')
        expect(@metadir.contents('/test/hello')).to match_array(['hello.txt'])
      end

      it 'should allow and delete files' do
        expect(@metadir.can_delete?('/test/hello/hello.txt')).to be_truthy
        @metadir.delete('/test/hello/hello.txt')
        expect(@metadir.contents('/test/hello')).to match_array(['emptydir'])
      end

      it 'should move directories at same level' do
        before = @metadir.contents('/test/hello')
        expect(@metadir.rename('/test/hello', '/test/moved')).to be_truthy
        expect(@metadir.directory?('/test/moved')).to be_truthy
        expect(@metadir.contents('/test/moved')).to match_array(before)
        expect(@metadir.read_file('/test/moved/hello.txt')).to eq("Hello World!\n")
      end

      it 'should move directories between different paths' do
        @metadir.mkdir('/test/other')
        @metadir.mkdir('/test/other/more')
        before = @metadir.contents('/test/hello')
        expect(@metadir.rename('/test/hello', '/test/other/more/hello')).to be_truthy
        expect(@metadir.contents('/test/other/more/hello')).to match_array(before)
        expect(@metadir.read_file('/test/other/more/hello/hello.txt')).to eq("Hello World!\n")
      end

      it 'should maintain filesystem statistics' do
        # remove a directory
        @metadir.rmdir('/test/hello/emptydir')

        # replace text for (the only)  existing file
        @metadir.write_to('/test/hello/hello.txt', 'new text')

        expect(@metadir.statistics('/')).to eq([8, 4, nil, nil])
      end
    end

    context 'with readonly access' do
      around(:each) do |example|
        #Simulate a different userid..
        FuseFS::Fuse::Root.context(fuse_context(-1, -1), &example)
      end

      before(:each) do
        expect(FuseFS::reader_uid).not_to eq(Process.uid)
        expect(FuseFS::reader_gid).not_to eq(Process.gid)
      end

      it 'should not allow directory creation' do
        expect(@metadir.can_mkdir?('/test/anydir')).to be_falsey
        expect(@metadir.can_mkdir?('/test/hello/otherdir')).to be_falsey
      end

      it 'should not allow file creation or write access' do
        expect(@metadir.can_write?('/test/hello/hello.txt')).to be_falsey
        expect(@metadir.can_write?('/test/hello/newfile')).to be_falsey
      end

      it 'should not allow file deletion' do
        expect(@metadir.can_delete?('/test/hello/hello.txt')).to be_falsey
      end

      it 'should not allow directory deletion' do
        expect(@metadir.can_rmdir?('/test/emptydir')).to be_falsey
      end

      it 'should not allow directory renames' do
        expect(@metadir.rename('/test/emptydir', '/test/otherdir')).to be_falsey
        #TODO and make sure it doesn't rename
      end

      it 'should not allow file renames' do
        expect(@metadir.rename('test/hello/hello.txt', 'test/hello.txt2')).to be_falsey
        #TODO and make sure it doesn't rename
      end
    end

    context 'with subdirectory containing another FuseFS' do
      around(:each) do |example|
        FuseFS::Fuse::Root.context(fuse_context(), &example)
      end

      before(:each) do
        @fusefs = double('mock_fusefs')
        @metadir.mkdir('/test')
        @metadir.mkdir('/test/fusefs', @fusefs)
      end

      api_methods = [:directory?, :file?, :contents, :executable?, :size, :times, :read_file, :can_write?, :can_delete?, :delete, :can_mkdir?, :can_rmdir?, :rmdir, :touch, :raw_open, :raw_truncate, :raw_read, :raw_write, :raw_close]
      api_methods.each do |method|
        it "should pass on #{method}" do
          arity = FuseFS::FuseDir.instance_method(method).arity().abs - 1
          args = Array.new(arity) { |i| i }
          expect(@fusefs).to receive(method).with('/path/to/file', *args).and_return('anything')
          @metadir.send(method, '/test/fusefs/path/to/file', *args)
        end
      end

      it 'should pass on :write_to' do
        expect(@fusefs).to receive(:write_to).with('/path/to/file', "new contents\n")
        @metadir.write_to('/test/fusefs/path/to/file', "new contents\n")
      end

      it 'should pass on :mkdir' do
        expect(@fusefs).to receive(:mkdir).with('/path/to/file', nil).once().and_raise(ArgumentError)
        expect(@fusefs).to receive(:mkdir).with('/path/to/file').once().and_return('true')
        @metadir.mkdir('/test/fusefs/path/to/file')
      end

      it 'should rename within same directory' do
        expect(@fusefs).to receive(:rename).with('/oldfile', '/newfile')
        @metadir.rename('/test/fusefs/oldfile', '/test/fusefs/newfile')
      end

      it 'should pass rename down common directories' do
        expect(@fusefs).to receive(:rename).with('/path/to/file', '/new/path/to/file')
        @metadir.rename('/test/fusefs/path/to/file', '/test/fusefs/new/path/to/file')
      end

      it 'should rename across directories if from_path is a FuseFS object that accepts extended rename' do
        expect(@fusefs).to receive(:rename).with('/path/to/file', '/nonfusepath',
                                                 an_instance_of(FuseFS::MetaDir)) do |myPath, extPath, extFS|
          extFS.write_to(extPath, 'look Mum, no hands!')
        end

        expect(@metadir.rename('/test/fusefs/path/to/file', '/test/nonfusepath')).to be_truthy
        expect(@metadir.read_file('/test/nonfusepath')).to eq('look Mum, no hands!')
      end

      it 'should quietly return false if from_path is a FuseFS object that does not accept extended rename' do
        expect(@fusefs).to receive(:rename).
                               with('/path/to/file', '/nonfusepath', an_instance_of(FuseFS::MetaDir)).
                               and_raise(ArgumentError)
        expect(@metadir.rename('/test/fusefs/path/to/file', '/test/nonfusepath')).to be_falsey

      end

      it 'should not attempt rename file unless :can_write? the destination' do
        expect(@fusefs).to receive(:can_write?).with('/newpath/to/file').and_return(false)
        @metadir.write_to('/test/aFile', 'some contents')
        expect(@metadir.rename('/test/aFile', '/test/fusefs/newpath/to/file')).to be_falsey
      end

      it 'should not attempt rename directory unless :can_mkdir? the destination' do
        expect(@fusefs).to receive(:can_mkdir?).with('/newpath/to/dir').and_return(false)
        @metadir.mkdir('/test/aDir', 'some contents')
        expect(@metadir.rename('/test/aDir', '/test/fusefs/newpath/to/dir')).to be_falsey
      end

      it 'should pass on #statistics' do
        expect(@fusefs).to receive(:statistics).with('/path/to/file')

        @metadir.statistics('test/fusefs/path/to/file')
      end

      it 'should pass on #statistics for root' do
        expect(@fusefs).to receive(:statistics).with('/')

        @metadir.statistics('test/fusefs')
      end
    end

  end
  context 'in a mounted FUSE filesystem' do

    before(:all) do
      metadir = FuseFS::MetaDir.new()
      mountpoint = Pathname.new(Dir.mktmpdir(['rfusefs', 'metadir']))

      metadir.mkdir('/test')
      metadir.write_to('/test/hello.txt', "Hello World!\n")
      metadir.xattr('/test/hello.txt')['user.test'] = 'an extended attribute'
      metadir.xattr('/test')['user.test'] = 'a dir attribute'
      FuseFS.mount(metadir, mountpoint)
      #Give FUSE some time to get started
      sleep(0.5)
      @metadir = metadir
      @mountpoint = mountpoint
    end

    after(:all) do
      FuseFS.unmount(@mountpoint)
      sleep(0.5)
      FileUtils.rm_r(@mountpoint)
    end

    let(:testdir) { mountpoint + 'test' }
    let(:testfile) { testdir + 'hello.txt' }
    let(:metadir) { @metadir}
    let(:mountpoint) { @mountpoint }

    it 'should list directory contents' do
      expect(testdir.entries()).to match_array(pathnames('.', '..', 'hello.txt'))
    end

    it 'should read files' do
      expect(testfile.file?).to be_truthy
      expect(testfile.read()).to eq("Hello World!\n")
    end

    it 'should read and write extended attributes from files' do
      x = Xattr.new(testfile.to_s)
      expect(x['user.test']).to eq('an extended attribute')

      x['user.new'] = 'new'

      expect(Xattr.new(testfile.to_s)['user.new']).to eq('new')
    end

    it 'should write extended attributes for directories' do
      x = Xattr.new(testdir.to_s)

      expect(x['user.test']).to eq('a dir attribute')
      x['user.new'] = 'new dir'

      expect(Xattr.new(testdir.to_s)['user.new']).to eq('new dir')
    end


    it 'should create directories' do
      newdir = testdir + 'newdir'
      newdir.mkdir()
      expect(newdir.directory?).to be_truthy
      expect(testdir.entries()).to match_array(pathnames('.', '..', 'hello.txt', 'newdir'))
    end

    it 'should create files' do
      newfile = testdir + 'newfile'
      newfile.open('w') do |file|
        file << "A new file\n"
      end
      expect(newfile.read).to eq("A new file\n")
    end

    it 'should move directories' do
      fromdir = testdir + 'fromdir'
      fromdir.mkdir()
      subfile = fromdir + 'afile'
      subfile.open('w') do |file|
        file << "testfile\n"
      end

      movedir = (mountpoint + 'movedir')
      expect(movedir.directory?).to be_falsey
      fromdir.rename(movedir)
      expect(movedir.directory?).to be_truthy

      subfile = movedir + 'afile'
      expect(subfile.file?).to be_truthy
      expect(subfile.read).to eq("testfile\n")
    end

    it 'should move files' do
      movefile = (mountpoint + 'moved.txt')
      expect(movefile.file?).to be_falsey
      expect(testfile).to be_truthy
      testfile.rename(movefile)
      expect(movefile.read).to eq("Hello World!\n")
    end


    it 'should report filesystem statistics' do
      bigfile = testdir + 'bigfile'
      bigfile.open('w') do |file|
        file << ('x' * 2048)
      end

      statfs = Sys::Filesystem.stat(mountpoint.to_s)

      # These are fixed
      expect(statfs.block_size).to eq(1024)
      expect(statfs.fragment_size).to eq(1024)

      # These are dependant on the tests above creating files/directories
      expect(statfs.files).to eq(8)
      statfs.files_available == 8

      # assume test are less than 1 block, so dependant on bigfile above
      expect(statfs.blocks).to eq(2)
      expect(statfs.blocks_available).to eq(0)
      expect(statfs.blocks_free).to eq(0)
    end
  end

end
