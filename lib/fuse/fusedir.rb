module FuseFS

    # This class is equivalent to using Object.new() as the virtual directory
    # for target for {FuseFS.start}. It exists primarily to document the API
    # but can also be used as a superclass for your filesystem
    #  
    # == Method call sequences
    # 
    # === Stat (getattr)
    #
    # FUSE itself will generally stat referenced files and validate the results
    # before performing any file/directory operations so this sequence is called
    # very often
    #   
    # 1. {#directory?} is checked first
    #    * {#can_write?} OR {#can_mkdir?} with .\_rfusefs_check\_ to determine write permissions
    #    * {#times} is called to determine atime,mtime,ctime info for the directory
    #
    # 2. {#file?} is checked next
    #    * {#can_write?}, {#executable?}, {#size}, {#times} are called to fill out the details
    #
    # 3. otherwise we tell FUSE that the path does not exist
    #
    # === List directory 
    # 
    # FUSE confirms the path is a directory (via stat above) before we call {#contents}
    #
    # FUSE will generally go on to stat each directory entry in the results
    #
    # === Reading files
    #
    # FUSE confirms path is a file before we call {#read_file}
    #
    # For fine control of file access see  {#raw_open}, {#raw_read}, {#raw_close}
    #
    # === Writing files
    #
    # FUSE confirms path for the new file is a directory
    #
    # * {#can_write?} is checked at file open
    # * {#write_to} is called when the file is flushed or closed
    #
    # See also {#raw_open}, {#raw_truncate}, {#raw_write}, {#raw_close}
    # 
    # === Deleting files
    #
    # FUSE confirms path is a file before we call {#can_delete?} then {#delete}
    #
    # === Creating directories
    #
    # FUSE confirms parent is a directory before we call {#can_mkdir?} then {#mkdir}
    #
    # === Deleting directories
    #
    # FUSE confirms path is a directory before we call {#can_rmdir?} then {#rmdir}
    #
    # === Renaming files and directories
    #
    # FUSE confirms the rename is valid (eg. not renaming a directory to a file)
    #
    # * Try {#rename} to see if the virtual directory wants to handle this itself
    # * If rename returns false/nil then we try to copy/delete (files only) ie.
    #   * {#file?}(from), {#can_write?}(to), {#can_delete?}(from) and if all true
    #   * {#read_file}(from), {#write_to}(to), {#delete}(from)
    # * otherwise reject the rename
    class FuseDir
        INIT_TIMES = Array.new(3,0)

        #   base,rest = split_path(path) 
        # @return [Array<String,String>] base,rest. base is the first directory in
        #                                path, and rest is nil> or the remaining path.
        #                                Typically if rest is not nil? you should 
        #                                recurse the paths 
        def split_path(path)
            cur, *rest = path.scan(/[^\/]+/)
            if rest.empty?
                [ cur, nil ]
            else
                [ cur, File::SEPARATOR + File.join(rest) ]
            end
        end

        #   base,*rest = scan_path(path)
        # @return [Array<String>] all directory and file elements in path. Useful
        #                         when encapsulating an entire fs into one object
        def scan_path(path)
            path.scan(/[^\/]+/)
        end

        # @abstract FuseFS api
        # @return [Boolean] true if path is a directory
        def directory?(path);return false;end

        # @abstract FuseFS api
        # @return [Boolean] true if path is a file
        def file?(path);end

        # @abstract FuseFS api
        # @return [Array<String>] array of file and directory names within path
        def contents(path);return [];end

        # @abstract FuseFS api
        # @return [Boolean] true if path is an executable file
        def executable?(path);return false;end

        # File size
        # @abstract FuseFS api
        # @return [Fixnum] the size in byte of a file (lots of applications rely on this being accurate )
        def size(path);return 0;end

        # File time information. RFuseFS extension.
        # @abstract FuseFS api
        # @return [Array<Fixnum, Time>] a 3 element array [ atime, mtime. ctime ] (good for rsync etc)
        def times(path);return INIT_TIMES;end

        # @abstract FuseFS api
        # @return [String] the contents of the file at path
        def read_file(path);return "";end

        # @abstract FuseFS api
        # @return [Boolean] true if the user can write to file at path
        def can_write?(path);return false;end

        # Write the contents of str to file at path
        # @abstract FuseFS api
        def write_to(path,str);end

        # @abstract FuseFS api
        # @return [Boolean] true if the user can delete the file at path
        def can_delete?(path);return false;end

        # Delete the file at path
        # @abstract FuseFS api
        def delete(path);end

        # @abstract FuseFS api
        # @return [Boolean] true if user can make a directory at path
        def can_mkdir?(path);return false;end

        # Make a directory at path
        # @abstract FuseFS api
        def mkdir(path);end

        # @abstract FuseFS api
        # @return [Boolean] true if user can remove a directory at path
        def can_rmdir?(path);return false;end

        # Remove the directory at path
        # @abstract FuseFS api
        def rmdir(path);end

        # Neat toy. Called when a file is touched or has its timestamp explicitly modified
        # @abstract FuseFS api
        def touch(path,modtime);end

        # Move a file or directory.
        # @abstract FuseFS api
        # @return [Object] non nil/false to indicate the rename has been handled,
        #                  otherwise will fallback to copy/delete
        def rename(from_path,to_path);end

        # Raw file access  
        # @abstract FuseFS api
        # @param mode [String] "r","w" or "rw", with "a" if file is opened for append
        # @param rfusefs [Boolean] will be "true" if RFuseFS extensions are available
        # @return [Object] a non nil object if you want lower level control of file operations
        #                  Under RFuseFS this object will be passed back in to the other raw
        #                  methods as the optional parameter _raw_
        #
        def raw_open(path,mode,rfusefs = nil);end

        # RFuseFS extension.
        #
        # Truncate file at path (or filehandle raw) to offset bytes. Called immediately after a file is opened
        # for write without append.
        #
        # This method can also be invoked (without raw) outside of an open file context. See
        # FUSE documentation on truncate() vs ftruncate()
        # @abstract FuseFS api
        def raw_truncate(path,off,raw=nil);end

        # Read _sz_ bytes from file at path (or filehandle raw) starting at offset off
        # 
        # @param [String] path
        # @param [Fixnum] offset
        # @param [Fixnum] size
        # @param [Object] raw the filehandle returned by {#raw_open}
        # @abstract FuseFS api
        def raw_read(path,off,size,raw=nil);end

        # Write _sz_ bytes from file at path (or filehandle raw) starting at offset off
        # @abstract FuseFS api
        def raw_write(path,off,sz,buf,raw=nil);end

        # Close the file previously opened at path (or filehandle raw)
        # @abstract FuseFS api
        def raw_close(path,raw=nil);end

    end

    DEFAULT_FS = FuseDir.new()
end
