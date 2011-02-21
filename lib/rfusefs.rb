# RFuseFS.rb

require 'rfusefs-fuse'
require 'metadir'

# This is FuseFS compatible module built over RFuse-NG

module FuseFS
  VERSION = "0.8.0"
  @mounts = { }

  # Start the FuseFS root at mountpoint with opts. *RFuseFS* extension
  # @param mountpoint [String] {mount_under}
  # @param root [Object] see {set_root}
  # @param opts [Array<String>] FUSE options see {mount_under}
  def FuseFS.start(mountpoint,root,*opts)
  	print "Starting FuseFS #{root} at #{mountpoint} with #{opts}\n"
    Signal.trap("TERM") { FuseFS.exit() }
    Signal.trap("INT") { FuseFS.exit() }
    FuseFS.set_root(root)
    FuseFS.mount_under(mountpoint,*opts)
    FuseFS.run()
    FuseFS.unmount()
  end

  # Forks {start} so you can access your filesystem with ruby File
  # operations (eg for testing). *RFuseFS* extension
  def FuseFS.mount(mountpoint,root = nil,*opts)
    
    pid = Kernel.fork do
    	FuseFS.start(mountpoint, root,*opts)
    end
    @mounts[mountpoint] = pid
    pid
  end
  
  # Unmount a filesystem
  # @param mountpoint [String] If nil?, unmounts the filesystem started with {start}
  #                            otherwise signals the forked process started with {mount}
  #                            to exit and unmount. *RFuseFS* extension
  def FuseFS.unmount(mountpoint=nil)
    
    if (mountpoint)
      if @mounts.has_key?(mountpoint)
        pid = @mounts[mountpoint]
        print "Sending TERM to forked FuseFS (#{pid})\n"
        Process.kill("TERM",pid)
        Process.waitpid(pid)
      else
      	  raise "Unknown mountpoint #{mountpoint}"
      end
    else
    	#Local unmount, make sure we only try to unmount once
    	if @fuse
    		print "Unmounting #{@fuse.mountname}\n"
    		@fuse.unmount()
    	end
    	@fuse = nil
    end
  end
  
  # Set the root virtual directory 
  # @param root [Object] an object implementing a subset of {FuseFS::API}
  def FuseFS.set_root(root)
    @root=root
  end
  
  # This will cause FuseFS to virtually mount itself under the given path. {set_root} must have
  # been called previously.
  # @param path [String] an existing directory where the filesystem will be virtually mounted
  # @param opts [Array<String>]  are FUSE options. Most likely, you will only want 'allow_other'
  #                              or 'allow_root'. The two are mutually exclusive in FUSE, but allow_other
  #                              will let other users, including root, access your filesystem. allow_root
  #                              will only allow root to access it.
  #      
  #                              Also available for FuseFS users are:
  #                              default_permissions, max_read=N, fsname=NAME.  
  #
  # For more information, see http://fuse.sourceforge.net
  def FuseFS.mount_under(path,*opts)    
    @fuse = RFuseFS.new(path,opts,[],@root)
  end
  
  # This is the main loop waiting on then executing filesystem operations from the
  # kernel. 
  #    
  # @note Running in a separate thread is generally not useful. In particular
  #       you cannot access your filesystem using ruby File operations.
  def FuseFS.run
  	unless @fuse
      raise "fuse is not mounted"
    end
    
    begin
    	io = IO.for_fd(@fuse.fd)
    rescue Errno::EBADF
    	raise "fuse not mounted"
    end
    
    @running = true
    while @running
    	begin
    		#We wake up every 2 seconds to check we are still running.
    		IO.select([io],[],[],2)
    		if  @fuse.process() < 0
    			@running = false
    		end    	    
    	rescue Errno::EBADF
    		@running = false
    	rescue Interrupt
    		#do nothing
    	end    		
    end
   end
  
  #  Exit the run loop and teardown FUSE   
  #  Most useful from Signal.trap() or Kernel.at_exit()  
  def FuseFS.exit
  	@running = false
  	
  	if @fuse
  		print "Exitting FUSE #{@fuse.mountname}\n"
  		@fuse.exit
  	end
  end
  
  # When the filesystem is accessed, the accessor's uid is returned
  # You can use this in determining your permissions, or even provide different files
  # for different users.
  def self.reader_uid
    Thread.current[:fusefs_reader_uid]
  end
  
  # When the filesystem is accessed, the accessor's gid is returned
  def self.reader_gid
    Thread.current[:fusefs_reader_gid]
  end
  
  # Not supported in RFuseFS (yet). The original FuseFS had special handling for editor
  # swap/backup but this does not seem to be required, eg for the demo filesystems.
  # If it is required it can be implemented in a filesystem
  def self.handle_editor(bool)
  	  #do nothing
  end

  # This class is equivalent to using Object.new() as the virtual directory
  # for target for FuseFS.start(). It exists only to document the API
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
  class API < FuseDir
      
      # @return [Boolean] true if path is a directory
      def directory?(path);end
 
      # @return [Boolean] true if path is a file
      def file?(path);end

      # @return [Array<String>] array of file and directory names within path
      def contents(path);return [];end
      
      # @return [Boolean] true if path is an executable file
      def executable?(path);end

      # File size
      # @return [Fixnum] the size in byte of a file (lots of applications rely on this being accurate )
      def size(path);return 0;end

      # File time information. RFuseFS extension.
      # @return [Array<Fixnum>] a 3 element array [ atime, mtime. ctime ] (good for rsync etc)
      def times(path);return INIT_TIMES;end

      # @return [String] the contents of the file at path
      def read_file(path);end

      # @return [Boolean] true if the user can write to file at path
      def can_write?(path);end

      # Write the contents of str to file at path
      def write_to(path,str);end

      # @return [Boolean] true if the user can delete the file at path
      def can_delete?(path);end

      # Delete the file at path
      def delete(path);end

      # @eturn [Boolean] true if user can make a directory at path
      def can_mkdir?(path);end

      # Make a directory at path
      def mkdir(path);end

      # @return [Boolean] true if user can remove a directory at path
      def can_rmdir?(path);end

      # Remove the directory at path
      def rmdir(path);end

      # Neat toy. Called when a file is touched or has its timestamp explicitly modified
      def touch(path,modtime);end

      # Move a file or directory.
      # @return [Object] non nil/false to indicate the rename has been handled,
      #                  otherwise will fallback to copy/delete
      def rename(from_path,to_path);end

      # Raw file access  
      # @param mode [String] "r","w" or "rw", with "a" if file is opened for append
      # @return [Object] a non nil object if you want lower level control of file operations
      #                  Under RFuseFS this object will be passed back in to the other raw
      #                  methods as the optional parameter _raw_
      #
      def raw_open(path,mode);end

      # RFuseFS extension.
      #
      # Truncate file at path (or filehandle raw) to offset bytes. Called immediately after a file is opened
      # for write without append.
      #
      # This method can also be invoked (without raw) outside of an open file context. See
      # FUSE documentation on truncate() vs ftruncate()
      def raw_truncate(path,off,raw=nil);end

      # Read _sz_ bytes from file at path (or filehandle raw) starting at offset off
      def raw_read(path,off,sz,raw=nil);end

      # Write _sz_ bytes from file at path (or filehandle raw) starting at offset off
      def raw_write(path,off,sz,buf,raw=nil);end

      # Close the file previously opened at path (or filehandle raw)
      def raw_close(path,raw=nil);end

  end
end
