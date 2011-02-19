# RFuseFS.rb

require 'rfusefs-fuse'


# This is FuseFS compatible module built over RFuse-NG
# Methods not originally part of FuseFS are indicated by *RFuseFS*
module FuseFS
  VERSION = "0.8.0"
  @mounts = { }

  # Shortcut to set_root(object);mount_under(path,*opts),run(),unmount(). *RFuseFS*   
  def FuseFS.start(mountpoint,root,*opts)
  	print "Starting FuseFS #{root} at #{mountpoint} with #{opts}\n"
    Signal.trap("TERM") { FuseFS.exit() }
    Signal.trap("INT") { FuseFS.exit() }
    FuseFS.set_root(root)
    FuseFS.mount_under(mountpoint,*opts)
    FuseFS.run()
    FuseFS.unmount()
  end

  # Forks FuseFS.start() so you can access your filesystem with ruby File
  # operations (eg for testing). *RFuseFS*
  def FuseFS.mount(mountpoint,root = nil,*opts)
    
    pid = Kernel.fork do
    	FuseFS.start(mountpoint, root,*opts)
    end
    @mounts[mountpoint] = pid
    pid
  end
    
  #  If path is nil, unmounts the filesystem started with FuseFS.start()
  #  otherwise signals the forked process started with FuseFS.mount(path,...)
  #  to exit and unmount. *RFuseFS*
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
  
  # Set the root virtual directory to <object>. All queries for obtaining
  # file information are directed at object. 
  def FuseFS.set_root(root)
    @root=root
  end
  
  # This will cause FuseFS to virtually mount itself under the given path.
  # 'path' is required to be a valid directory in your actual filesystem.
  #
  # 'opt's are FUSE options. Most likely, you will only want 'allow_other'
  # or 'allow_root'. The two are mutually exclusive in FUSE, but allow_other
  # will let other users, including root, access your filesystem. allow_root
  # will only allow root to access it.
  #      
  # Also available for FuseFS users are:
  # default_permissions, max_read=N, fsname=NAME.  
  #
  # For more information, look at FUSE.
  def FuseFS.mount_under(path,*opts)    
    @fuse = RFuseFS.new(path,opts,[],@root)
  end
  
  # This is the final step to make your virtual filesystem accessible.
  #    
  # Note: Running in a separate thread is generally not useful. In particular
  # you cannot access your filesystem using ruby File operations.
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
  # swap/backup files. Either turn this behaviour off in your editor or implement
  # something for your filesystem
  def self.handle_editor(bool)
  	  #do nothing
  end
end

