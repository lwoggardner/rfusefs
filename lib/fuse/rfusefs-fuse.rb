# RFuseFS - FuseFS over RFuse
require 'rfuse'
require 'fcntl'

module FuseFS
    #Which raw api should we use?
    RFUSEFS_COMPATIBILITY = true unless FuseFS.const_defined?(:RFUSEFS_COMPATIBILITY)

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
            @size = 0
        end

        def read(offset,size)
            contents[offset,size]
        end

        def create
            @contents = ""
            @modified = true
        end

        def write(offset,data)
            # TODO: why append?
            if append? || offset >= contents.length
                #ignore offset
                #TODO: should this zero fill?
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
            writing? && (flags & Fcntl::O_APPEND != 0)
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

    # Implements RFuseFS
    # The path supplied to these methods is generally validated by FUSE itself
    # with a prior "getattr" call so we do not revalidate here.
    # http://sourceforge.net/apps/mediawiki/fuse/index.php?title=FuseInvariants
    class RFuseFS
        CHECK_FILE="/._rfuse_check_"

        def initialize(root)
            @root = root
            @created_files = { }

            # Keep track of changes to file counts and sizes made via Fuse - for #statfs
            @adj_nodes = 0
            @adj_size = 0

            #Define method missing for our filesystem
            #so we can just call all the API methods as required.
            def @root.method_missing(method,*args)
                # our filesystem might implement method_missing itself
                super
            rescue NoMethodError
                DEFAULT_FS.send(method,*args)
            end
        end

        def readdir(ctx,path,filler,offset,ffi)

            return wrap_context(ctx,__method__,path,filler,offset,ffi) if ctx

            #Always have "." and ".."
            filler.push(".",nil,0)
            filler.push("..",nil,0)

            files = @root.contents(path)

            files.each do | filename |
                filler.push(filename,nil,0)
            end

        end

        def getattr(ctx,path)

            return wrap_context(ctx,__method__,path) if ctx

            uid = Process.uid
            gid = Process.gid

            if  path == "/" || @root.directory?(path)
                #set "w" flag based on can_mkdir? || can_write? to path + "/._rfuse_check"
                write_test_path = (path == "/" ? "" : path) + CHECK_FILE

                mode = (@root.can_mkdir?(write_test_path) || @root.can_write?(write_test_path)) ? 0777 : 0555
                atime,mtime,ctime = @root.times(path)
                #nlink is set to 1 because apparently this makes find work.
                return RFuse::Stat.directory(mode,{ :uid => uid, :gid => gid, :nlink => 1, :atime => atime, :mtime => mtime, :ctime => ctime })
            elsif @created_files.has_key?(path)
                return @created_files[path]
            elsif @root.file?(path)
                #Set mode from can_write and executable
                mode = 0444
                mode |= 0222 if @root.can_write?(path)
                mode |= 0111 if @root.executable?(path)
                size = size(path)
                atime,mtime,ctime = @root.times(path)
                return RFuse::Stat.file(mode,{ :uid => uid, :gid => gid, :size => size, :atime => atime, :mtime => mtime, :ctime => ctime })
            else
                raise Errno::ENOENT.new(path)
            end

        end #getattr

        def mkdir(ctx,path,mode)

            return wrap_context(ctx,__method__,path,mode) if ctx

            unless @root.can_mkdir?(path)
                raise Errno::EACCES.new(path)
            end

            @root.mkdir(path)
            @adj_nodes += 1
        end #mkdir

        def mknod(ctx,path,mode,major,minor)

            return wrap_context(ctx,__method__,path,mode,major,minor) if ctx

            unless ((RFuse::Stat::S_IFMT & mode) == RFuse::Stat::S_IFREG ) && @root.can_write?(path)
                raise Errno::EACCES.new(path)
            end

            now = Time.now
            stat = RFuse::Stat.file(mode,{ :uid => Process.uid, :gid => Process.gid, :atime => now, :mtime => now, :ctime => now })

            @created_files[path] = stat
            @adj_nodes += 1
        end #mknod

        #ftruncate - eg called after opening a file for write without append
        #sizes are adjusted at file close
        def ftruncate(ctx,path,offset,ffi)

            return wrap_context(ctx,__method__,path,offset,ffi) if ctx

            fh = ffi.fh

            if fh.raw
                @root.raw_truncate(path,offset,fh.raw)
                if (offset <= 0)
                    fh.contents = ""
                else
                    fh.contents = fh.contents[0..offset]
                end
            end
        end

        #truncate a file outside of open files
        def truncate(ctx,path,offset)
            return wrap_context(ctx,__method__,path,offset) if ctx

            unless @root.can_write?(path)
                raise Errno::EACESS.new(path)
            end

            current_size = size(path)
            unless @root.raw_truncate(path,offset)
                contents = @root.read_file(path)
                if (offset <= 0)
                   @root.write_to(path,"")
                elsif offset < contents.length
                    @root.write_to(path,contents[0..offset] )
                end
            end
            @adj_size = @adj_size - current_size + (offset <= 0 ? 0 : offset)
        end #truncate

        # Open. Create a FileHandler and store in fuse file info
        # This will be returned to us in read/write
        # No O_CREATE (mknod first?), no O_TRUNC (truncate first)
        def open(ctx,path,ffi)
            return wrap_context(ctx,__method__,path,ffi) if ctx
            fh = FileHandle.new(path,ffi.flags)

            #Save the value return from raw_open to be passed back in raw_read/write etc..
            if (FuseFS::RFUSEFS_COMPATIBILITY)
                fh.raw = @root.raw_open(path,fh.raw_mode,true)
            else
                fh.raw = @root.raw_open(path,fh.raw_mode)
            end

            unless fh.raw
                if fh.rdonly?
                    fh.contents = @root.read_file(path)
                elsif fh.writing?
                    unless @root.can_write?(path)
                        raise Errno::EACCES.new(path)
                    end

                    if @created_files.has_key?(path)
                        fh.create
                    else
                        if fh.rdwr? || fh.append?
                            fh.contents = @root.read_file(path)
                        else #wronly && !append
                            #We should get a truncate 0, but might as well play it safe
                            fh.contents = ""
                        end
                    end
                else
                    raise Errno::ENOPERM.new(path)
                end
            end

            #If we get this far, save our filehandle in the FUSE structure
            ffi.fh=fh
        end

        def read(ctx,path,size,offset,ffi)
            return wrap_context(ctx,__method__,path,size,offset,ffi) if ctx

            fh = ffi.fh

            if fh.raw
                if FuseFS::RFUSEFS_COMPATIBILITY
                    return @root.raw_read(path,offset,size,fh.raw)
                else
                    return @root.raw_read(path,offset,size)
                end
            elsif offset >= 0
                return fh.read(offset,size)
            else
                #TODO: Raise? what does a negative offset mean
                return ""
            end
        rescue EOFError
            return ""
        end

        def write(ctx,path,buf,offset,ffi)
            return wrap_context(ctx,__method__,path,buf,offset,ffi) if ctx
            fh = ffi.fh

            if fh.raw
                if FuseFS::RFUSEFS_COMPATIBILITY
                    return @root.raw_write(path,offset,buf.length,buf,fh.raw)
                else
                    @root.raw_write(path,offset,buf.length,buf)
                    return buf.length
                end
            else
                return fh.write(offset,buf)
            end
        end

        def fsync(ctx,path,datasync,ffi)
            return wrap_context(ctx,__method__,path,datasync,ffi) if ctx
            fh = ffi.fh

            if fh && fh.raw
                if FuseFS::RFUSEFS_COMPATIBILITY
                    @root.raw_sync(path,datasync != 0,fh.raw)
                else
                    @root.raw_sync(path,datasync != 0)
                end
            else
                flush(nil,path,ffi)
            end
        end

        def flush(ctx,path,ffi)
            return wrap_context(ctx,__method__,path,ffi) if ctx
            fh = ffi.fh

            if fh && !fh.raw && fh.modified?
                #write contents to the file and mark it unmodified
                @root.write_to(path,fh.flush())
                #if it was created with mknod it now exists in the filesystem...
                @created_files.delete(path)
            end
        end

        def release(ctx,path,ffi)
            return wrap_context(ctx,__method__,path,ffi) if ctx


            fh = ffi.fh
            if fh && fh.raw
                if (FuseFS::RFUSEFS_COMPATIBILITY)
                    @root.raw_close(path,fh.raw)
                else
                    @root.raw_close(path)
                end
                # if was handled as raw, then assume the file has now been created (or not)
                @created_files.delete(path)
            else
                # Probably just had flush called, but no harm calling it again
                flush(nil,path,ffi)
            end
        end

        #def chmod(path,mode)
        #end

        #def chown(path,uid,gid)
        #end

        def utime(ctx,path,actime,modtime)
            return wrap_context(ctx,__method__,path,actime,modtime) if ctx

            #Touch...
            @root.touch(path,modtime) if @root.respond_to?(:touch)
        end

        def unlink(ctx,path)
            return wrap_context(ctx,__method__,path) if ctx

            unless @root.can_delete?(path)
                raise Errno::EACCES.new(path)
            end

            @adj_size = @adj_size - size(path)

            @created_files.delete(path)
            @root.delete(path)
        end

        def rmdir(ctx,path)
            return wrap_context(ctx,__method__,path) if ctx

            unless @root.can_rmdir?(path)
                raise Errno::EACCES.new(path)
            end
            @root.rmdir(path)
        end

        #def symlink(path,as)
        #end

        def rename(ctx,from,to)
            return wrap_context(ctx,__method__,from,to) if ctx

            if @root.rename(from,to)
                # nothing to do
            elsif @root.file?(from) && @root.can_write?(to) &&  @root.can_delete?(from)
                contents = @root.read_file(from)
                @root.write_to(to,contents)
                @root.delete(from)
            else
                raise Errno::EACCES.new("Unable to move directory #{from}")
            end
        end

        #def link(path,as)
        #end

        def setxattr(ctx,path,name,value,flags)
            return wrap_context(ctx,__method__,path,name,value,flags) if ctx
            @root.xattr(path)[name]=value
        end

        def getxattr(ctx,path,name)
            return wrap_context(ctx,__method__,path,name) if ctx
            result = @root.xattr(path)[name]
            raise Errno::ENODATA.new("No attribute #{name}") unless result
            result.to_s
        end

        def listxattr(ctx,path)
            return wrap_context(ctx,__method__,path) if ctx
            @root.xattr(path).keys
        end

        def removexattr(ctx,path,name)
            return wrap_context(ctx,__method__,path,name) if ctx
            @root.xattr(path).delete(name)
        end

        #def opendir(path,ffi)
        #end

        #def releasedir(path,ffi)
        #end

        #
        #def fsyncdir(path,meta,ffi)
        #end

        # Some random numbers to show with df command
        # bsize preferred block size = 1K unless @root provides something different
        # frsize = bsize (but apparently unused)
        # blocks = total number of blocks
        # bfree = number of free blocks
        # bavail = bfree if mounted -o allow_other
        # files = count of all files
        # ffree - count of free file inode
        #
        def statfs(ctx,path)
            return wrap_context(ctx,__method__,path) if ctx
            block_size = 1024

            stats = @root.statistics(path)
            case stats
            when Array
                used_space, used_files, total_space, total_files = stats
                used_files ||= 0
                used_space ||= 0
                total_files ||= used_files
                total_space ||= used_space
                result = RFuse::StatVfs.new(
                  "bsize" => block_size,
                  "frsize" => block_size,
                  "blocks" => total_space / block_size,
                  "bfree" => (total_space - used_space)/block_size,
                  "bavail" => (total_space - used_space)/block_size,
                  "files" => total_files,
                  "ffree" => (total_files - used_files)
                )
                return result
            else
                #expected to quack like rfuse:statvfs
                return stats
            end
        end

    def mounted()
        @root.mounted()
    end

    def unmounted()
        @root.unmounted()
    end

    def self.context(ctx,&block)
        begin
            Thread.current[:fusefs_reader_uid] = ctx.uid
            Thread.current[:fusefs_reader_gid] = ctx.gid
            yield
        ensure
            Thread.current[:fusefs_reader_uid] = nil
            Thread.current[:fusefs_reader_gid] = nil
        end
    end

    private

    def wrap_context(ctx,method,*args)
        self.class.context(ctx) { send(method,nil,*args) }
    end

    def size(path)
        @root.respond_to?(:size) ? @root.size(path) : @root.read_file(path).length
    end

    end #class RFuseFS
end #Module FuseFS
