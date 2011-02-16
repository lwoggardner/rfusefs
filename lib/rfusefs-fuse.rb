#!/usr/bin/ruby

# RFuseFS - FuseFS over RFuse
require 'rfuse_ng'
require 'fcntl'
require 'forwardable'
require 'pp'

module FuseFS
  #Which raw api should we use?
  RFUSEFS_COMPATIBILITY = true unless FuseFS.const_defined?(:RFUSEFS_COMPATIBILITY)
  
  
  # File/Directory attributes
  class Stat
  	S_IFMT   = 0170000 # Format mask
    S_IFDIR  = 0040000 # Directory.  
    S_IFCHR  = 0020000 # Character device.
    S_IFBLK  = 0060000 # Block device.
    S_IFREG  = 0100000 # Regular file. 
    S_IFIFO  = 0010000 # FIFO. 
    S_IFLNK  = 0120000 # Symbolic link. 
    S_IFSOCK = 0140000 # Socket. 
    
    def self.directory(mode=0,values = { })
      return self.new(S_IFDIR,mode,values)
    end
    
    def self.file(mode=0,values = { })
      return self.new(S_IFREG,mode,values)
    end
    
    attr_accessor :uid,:gid,:mode,:size,:atime,:mtime,:ctime
    attr_accessor :dev,:ino,:nlink,:rdev,:blksize,:blocks
    
    def initialize(type,permissions,values = { })
      values[:mode] = ((type & S_IFMT) | (permissions & 07777))
      @uid,@gid,@size,@mode,@atime,@mtime,@ctime,@dev,@ino,@nlink,@rdev,@blksize,@blocks = Array.new(13,0)
      values.each_pair do |k,v|
        instance_variable_set("@#{ k }",v)
      end
    end
  end
  
  # Filesystem attributes (eg for df output)
  class StatVfs
    attr_accessor :f_bsize,:f_frsize,:f_blocks,:f_bfree,:f_bavail
    attr_accessor :f_files,:f_ffree,:f_favail,:f_fsid,:f_flag,:f_namemax
    #values can be symbols or strings but drop the pointless f_ prefix
    def initialize(values={ })
      @f_bsize, @f_frsize, @f_blocks, @f_bfree, @f_bavail, @f_files, @f_ffree, @f_favail,@f_fsid, @f_flag,@f_namemax = Array.new(13,0)
      values.each_pair do |k,v|
        instance_variable_set("@f_#{ k }",v)
      end
    end
  end
  
  
  
  
  class FileHandle
    @@fh = 0
    attr_reader :id,:flags,:path
    attr_accessor :raw,:contents
    def initialize(path,flags)
      @id = (@@fh += 1)
      @flags = flags
      @path = path
      @modified = false
      @contents = ""
    end
    
    def read(offset,size)
      contents[offset,size]
    end
    
    def write(offset,data)
      if append? || offset >= contents.length
        #ignore offset
        contents << data
      else
        contents[offset,data.length]=data
      end
      @modified = true
      return data.length
    end
    
    def flush
      @modified = false
      contents
    end
    
    def modified?
      @modified
    end
    
    def accmode
      flags & Fcntl::O_ACCMODE
    end
    
    def rdwr?
      accmode == Fcntl::O_RDWR
    end
    
    def wronly?
      accmode == Fcntl::O_WRONLY
    end
    
    def rdonly?
      accmode == Fcntl::O_RDONLY
    end
    
    def append?
      writing? && flags & Fcntl::O_APPEND
    end
    
    def reading?
      rdonly? || rdwr?
    end
    
    def writing?
      wronly? || rdwr?
    end
    
    def raw_mode
      mode_str = case accmode
      when Fcntl::O_RDWR; "rw"
      when Fcntl::O_RDONLY; "r"
      when Fcntl::O_WRONLY; "w"
      end
      
      mode_str << "a" if append?
      return mode_str
    end
  end
  
  #This is the class associated with the rfuse_ng extension
  #We use a delegator here so we can test the RFuseFSAPI
  #without actually mounting FUSE
  class RFuseFS < RFuse::Fuse
  	CHECK_FILE="/._rfuse_check_"
  	  
  	# TODO, wrap all delegate methods in a context block
    extend Forwardable
    def_delegators(:@delegate,:readdir,:getattr,:mkdir,:mknod,
    :truncate,:open,:read,:write,:flush,:release,
    :utime,:rmdir,:unlink,:rename)
    
    def initialize(mnt,kernelopt,libopt,root)
      @delegate = RFuseFSAPI.new(root)
      super(mnt.to_s,kernelopt,libopt)
      
    end
    
    def init(ctx,rfuseconninfo)
      #print "Init #{rfuseconninfo.inspect}\n"
      return nil
    end
    
    private
    def self.context(ctx)
      begin
        Thread.current[:fusefs_reader_uid] = ctx.uid
        Thread.current[:fusefs_reader_gid] = ctx.gid
        yield if block_given?
        ensure
        Thread.current[:fusefs_reader_uid] = nil
        Thread.current[:fusefs_reader_gid] = nil
      end
    end
  end #class RFuseFS
  
  class RFuseFSAPI
     #require 'tracecalls'
  	 #include TraceCalls

    #If not implemented by our filesystem these values are returned
    API_OPTIONAL_METHODS = {
    :can_write? => false,
    :write_to => nil,
    :can_delete? => false,
    :delete => nil,
    :can_mkdir? => false,
    :mkdir => nil,
    :can_rmdir? => false,
    :rmdir => nil,
    :touch => nil,
    :rename => nil,
    :raw_open => nil,
    :raw_read => nil,
    :raw_write => nil,
    :raw_close => nil,
    :size => 0,
    :times => Array.new(3,0),
    :contents => Array.new(),
    :file? => false,
    :directory? => false,
    :executable? => false
    }
    
    def initialize(root)
      @root = root
      @created_files = { }
      
      #Define method missing for our filesystem
      #so we can just call all the API methods as required.
      def @root.method_missing(method,*args)
        if API_OPTIONAL_METHODS.has_key?(method)
          return API_OPTIONAL_METHODS[method]
        else
          super
        end
        
      end
    end
    
    
    def readdir(ctx,path,filler,offset,ffi)
      RFuseFS.context(ctx) do
        #Apparently the directory? check is unnecessary - getAttr has already been called
        #and checked.
        #http://sourceforge.net/apps/mediawiki/fuse/index.php?title=FuseInvariants
        #unless @root.directory?(path)
        #  raise Errno::ENOTDIR.new(path)
        #end
        
        #Always have "." and ".."
        filler.push(".",nil,0)
        filler.push("..",nil,0)
        
        @root.contents(path).each do | filename |
          filler.push(filename,nil,0)
        end
      end
    end
    
    def getattr(ctx,path)
      RFuseFS.context(ctx) do
        uid = Process.gid
        gid = Process.uid
        
        if  path == "/" || @root.directory?(path)
          #set "w" flag based on can_mkdir? || can_write? to path + "/._rfuse_check"
          write_test_path = (path == "/" ? "" : path) + RFuseFS::CHECK_FILE
          
          mode = (@root.can_mkdir?(write_test_path) || @root.can_write?(write_test_path)) ? 0777 : 0555
          atime,mtime,ctime = @root.times(path)
          #nlink is set to 1 because apparently this makes find work.
          return Stat.directory(mode,{ :uid => uid, :gid => gid, :nlink => 1, :atime => atime, :mtime => mtime, :ctime => ctime })
        elsif @created_files.has_key?(path)
          now = Time.now.to_i
          return Stat.file(@created_files[path],{ :uid => uid, :gid => gid, :atime => now, :mtime => now, :ctime => now })
        elsif @root.file?(path)
          #Set mode from can_write and executable
          mode = 0444
          mode |= 0222 if @root.can_write?(path)
          mode |= 0111 if @root.executable?(path)
          size = @root.size(path)
          atime,mtime,ctime = @root.times(path)
          return Stat.file(mode,{ :uid => uid, :gid => gid, :size => size, :atime => atime, :mtime => mtime, :ctime => ctime })
        else
        	raise Errno::ENOENT.new(path)
        end
      end
    end #getattr
    
    def mkdir(ctx,path,mode)
      RFuseFS.context(ctx) do
        #Not if we are already a directory or file
        
        if @root.directory?(path) || @root.file?(path) || @created_files[path]
          raise Errno::EEXIST.new(path)
        end
        
        unless @root.can_mkdir?(path)
          raise Errno::EACCES.new(path)
        end
        
        @root.mkdir(path)
      end
    end #mkdir
    
    def mknod(ctx,path,mode,dev)
      RFuseFS.context(ctx) do
      	  
        if (@root.file?(path) || @root.directory?(path) || @created_files[path])
          raise Errno::EEXIST.new(path)
        end
        
        unless ((Stat::S_IFMT & mode) == Stat::S_IFREG ) && @root.can_write?(path)
          raise Errno::EACCES.new(path)
        end
      end
      
      printf("mknod: %o\n",mode)
      @created_files[path] = mode
    end #mknod
    
    #truncate a file (note not ftruncate - so this is outside of open files)
    def truncate(ctx,path,offset)
      RFuseFS.context(ctx) do
        
        #unnecessary?
        unless @root.file?(path)
          raise Errno:ENOENT.new(path)
        end
        
        unless @root.can_write?(path)
          raise Errno::EACESS.new(path)
        end
        
        unless @root.raw_truncate(path,offset)
          contents = @root.read_file(path)
          if (offset <= 0)
            @root.write_to(path,"")
          elsif offset < contents.length
            @root.write_to(path,contents[0..offset] )
          end
        end
      end
    end #truncate
    
    # Open. Create a FileHandler and store in fuse file info
    # This will be returned to us in read/write
    # No O_CREATE (mknod first?), no O_TRUNC (truncate first)
    def open(ctx,path,ffi)
      RFuseFS.context(ctx) do
        fh = FileHandle.new(path,ffi.flags)
        
        #Save the value return from raw_open to be passed back in raw_read/write etc..
        if (FuseFS::RFUSEFS_COMPATIBILITY)
          fh.raw = @root.raw_open(path,fh.raw_mode,true)
        else
          fh.raw = @root.raw_open(path,fh.raw_mode)
        end
        
        unless fh.raw
          
          if fh.rdonly?
            unless @root.file?(path)
              raise Errno::ENOENT.new(path)
            end
            fh.contents = @root.read_file(path)
            
          elsif fh.rdwr? || fh.wronly?
            unless @root.can_write?(path)
              raise Errno::EACCES.new(path)
            end
            
            if @created_files.has_key?(path)
              #we have an empty file
              fh.contents = "";
            elsif @root.file?(path)
              if fh.rdwr? || fh.append?
                fh.contents = @root.read_file(path)
              else #wronly && !append
                fh.contents = ""
              end
            else
              raise Errno::ENOENT.new(path)
            end
          else
            raise Errno::ENOPERM.new(path)
          end
        end
        #If we get this far, save our filehandle in the FUSE structure
        ffi.fh=fh
        
      end #context
    end
    
    def read(ctx,path,size,offset,ffi)
      fh = ffi.fh
      
      if fh.raw
        RFuseFS.context(ctx) do
          if FuseFS::RFUSEFS_COMPATIBILITY
            return @root.raw_read(path,offset,size,fh.raw)
          else
            return @root.raw_read(path,offset,size)
          end
        end
      elsif offset >= 0
        return fh.read(offset,size)
      else
        return 0
      end
      
      
    end
    
    def write(ctx,path,buf,offset,ffi)
      fh = ffi.fh
      
      if fh.raw
        RFuseFS.context(ctx) do
          if FuseFS::RFUSEFS_COMPATIBILITY
            return @root.raw_write(path,offset,buf.length,buf,fh.raw)
          else
            @root.raw_write(path,offset,buf.length,buf)
            return buf.length
          end
        end
      else
        return fh.write(offset,buf)
      end
      
    end
    
    def flush(ctx,path,ffi)
      fh = ffi.fh
      
      #unnecessary?
      unless fh && fh.path == path
        raise Errno::EBADF.new(path)
      end
      
      RFuseFS.context(ctx) do
        
        if fh.raw
          if (FuseFS::RFUSEFS_COMPATIBILITY)
            @root.raw_close(path,fh.raw)
          else
            @root.raw_close(path)
          end
        elsif fh.modified?
          #write contents to the file and mark it unmodified
          @root.write_to(path,fh.flush())
        end
      end
      
      #if file was created with mknod it now exists in the filesystem so we don't need to
      #keep track of it anymore
      @created_files.delete(path)
    end
    
    def release(ctx,path,ffi)
      
    end
    
    
    
    #def chmod(ctx,path,mode)
    #end
    
    #def chown(ctx,path,uid,gid)
    #end
    
    def utime(ctx,path,actime,modtime)
      #Touch...
      if @root.respond_to?(:touch)
        @root.touch(path,modtime)
      end
    end
    
    def unlink(ctx,path)
      RFuseFS.context(ctx) do
        unless @root.can_delete?(path)
          raise Errno::EACCES.new(path)
        end
        
        @root.delete(path)
      end
    end
    
    def rmdir(ctx,path)
      RFuseFS.context(ctx) do
        unless @root.can_rmdir?(path)
          raise Errno::EACCES.new(path)
        end
        @root.rmdir(path)
      end
    end
    
    #def symlink(ctx,path,as)
    #end
    
    def rename(ctx,from,to)
      RFuseFS.context(ctx) do
        if @root.rename(from,to)
          #nothing to do
        elsif @root.file?(from) && @root.can_write(to) &&  @root.can_delete(from)
          contents = @root.read_file(from)
          @root.write_to(to,contents)
          @root.delete(from)
        else
          raise Errno:EACCES
        end
      end
    end
    
    #def link(ctx,path,as)
    #end
    
    # def setxattr(ctx,path,name,value,size,flags)
    # end
    
    # def getxattr(ctx,path,name,size)
    # end
    
    # def listxattr(ctx,path,size)
    # end
    
    # def removexattr(ctx,path,name)
    # end
    
    #def opendir(ctx,path,ffi)
    #end
    
    #def releasedir(ctx,path,ffi)
    #end
    
    #def fsyncdir(ctx,path,meta,ffi)
    #end
    
    # Some random numbers to show with df command
    #def statfs(ctx,path)   
    #end
    
  end #class RFuseFSAPI
  
end #Module FuseFS
